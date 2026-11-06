import CoreData
import Core
import Foundation
import Photos

/// CoreData implementation of PhotoClusterRepository
public final class CoreDataPhotoClusterRepository: PhotoClusterRepository {
    enum Constants {
        static let maxInPredicateBatchSize = 500
    }

    struct ClusterData: Sendable {
        let id: UUID
        let createdAt: Date
        let averageSimilarity: Float
        let assets: [AssetData]
    }

    struct AssetData: Sendable {
        let localIdentifier: String
        let creationDate: Date?
        let modificationDate: Date?
        let pixelWidth: Int
        let pixelHeight: Int
        let isFavorite: Bool
    }

    private let persistence: PersistenceController
    private let changeDetector: any PhotoLibraryChangeDetecting

    public init(
        persistence: PersistenceController = .shared,
        changeDetector: any PhotoLibraryChangeDetecting = PhotoKitChangeDetector()
    ) {
        self.persistence = persistence
        self.changeDetector = changeDetector
    }
    
    /// Resolves stored clusters to `PHAsset`s off the main thread.
    ///
    /// `PHAsset.fetchAssets` is a synchronous round trip to the photo library
    /// service. One call per cluster on the main queue added up past the
    /// 10-second scene-update watchdog on large libraries (0x8BADF00D), so all
    /// identifiers are fetched in a few batches on a detached task instead.
    public func loadClusters() async throws -> [PhotoCluster] {
        try await loadResolvedClusters(
            fetch: { identifiers in
                var assets: [(localIdentifier: String, asset: PHAsset)] = []
                assets.reserveCapacity(identifiers.count)
                PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
                    .enumerateObjects { asset, _, _ in
                        assets.append((asset.localIdentifier, asset))
                    }
                return assets
            },
            build: { cluster, assets in
                PhotoCluster(
                    id: cluster.id,
                    assets: assets,
                    createdAt: cluster.createdAt,
                    averageSimilarity: cluster.averageSimilarity
                )
            }
        )
    }

    /// Reads the stored clusters, resolves their identifiers through `fetch`
    /// in batches on a detached task, and builds one `Output` per cluster that
    /// still has assets. `fetch` and `build` never run on the caller's actor.
    func loadResolvedClusters<Asset, Output: Sendable>(
        batchSize: Int = Constants.maxInPredicateBatchSize,
        fetch: @escaping @Sendable ([String]) -> [(localIdentifier: String, asset: Asset)],
        build: @escaping @Sendable (ClusterData, [Asset]) -> Output
    ) async throws -> [Output] {
        try Task.checkCancellation()
        let clusterData = try await loadClusterData()
        guard !clusterData.isEmpty else { return [] }

        let task = Task.detached(priority: .userInitiated) { () throws -> [Output] in
            let start = ContinuousClock().now
            var resolved: [String: (order: Int, asset: Asset)] = [:]
            for chunk in Self.uniqueLocalIdentifiers(in: clusterData).chunked(into: batchSize) {
                try Task.checkCancellation()
                for entry in fetch(chunk) where resolved[entry.localIdentifier] == nil {
                    resolved[entry.localIdentifier] = (resolved.count, entry.asset)
                }
            }
            try Task.checkCancellation()
            let outputs = Self.assembleClusters(clusterData, resolved: resolved)
                .map { build($0.cluster, $0.assets) }
            AppLog.storage.debug("\(AppLog.tag(.storage, "Load clusters count=\(outputs.count) assets=\(resolved.count) duration=\(start.duration(to: ContinuousClock().now))"))")
            return outputs
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static func uniqueLocalIdentifiers(in clusterData: [ClusterData]) -> [String] {
        var seen = Set<String>()
        var identifiers: [String] = []
        for cluster in clusterData {
            for asset in cluster.assets where seen.insert(asset.localIdentifier).inserted {
                identifiers.append(asset.localIdentifier)
            }
        }
        return identifiers
    }

    /// Pairs each stored cluster with the assets PhotoKit still knows.
    ///
    /// Keeps the cluster order, drops identifiers missing from `resolved`, and
    /// skips clusters left empty. Assets inside a cluster keep the order the
    /// fetch returned them in, as the former one-fetch-per-cluster code did,
    /// so a cluster's thumbnail (`assets.first`) does not change.
    static func assembleClusters<Asset>(
        _ clusterData: [ClusterData],
        resolved: [String: (order: Int, asset: Asset)]
    ) -> [(cluster: ClusterData, assets: [Asset])] {
        clusterData.compactMap { cluster in
            let entries = cluster.assets
                .compactMap { resolved[$0.localIdentifier] }
                .sorted { $0.order < $1.order }
            return entries.isEmpty ? nil : (cluster, entries.map(\.asset))
        }
    }

    public func loadClusterSnapshots() async throws -> [PhotoClusterSnapshot] {
        try await loadClusterData().map { clusterData in
            PhotoClusterSnapshot(
                id: clusterData.id,
                createdAt: clusterData.createdAt,
                averageSimilarity: clusterData.averageSimilarity,
                assets: clusterData.assets.map { assetData in
                    PhotoClusterAssetSnapshot(
                        localIdentifier: assetData.localIdentifier,
                        creationDate: assetData.creationDate,
                        modificationDate: assetData.modificationDate,
                        pixelWidth: assetData.pixelWidth,
                        pixelHeight: assetData.pixelHeight,
                        isFavorite: assetData.isFavorite
                    )
                }
            )
        }
    }
    
    @MainActor
    public func saveClusters(_ clusters: [PhotoCluster]) async throws {
        try await saveClusterData(makeClusterData(from: clusters))
    }
    
    public func deleteAllClusters() async throws {
        try await persistence.performBackgroundTask { context in
            let request = ClusterEntity.fetchRequest()
            let clusters = try context.fetch(request)
            for cluster in clusters {
                let photos = cluster.photos as? Set<PhotoEntity> ?? []
                for photo in photos {
                    photo.cluster = nil
                }
                context.delete(cluster)
            }
            try context.save()
        }
    }
    
    public func getLastScanDate() async -> Date? {
        await loadScanMetadata()?.lastScanDate
    }

    public func loadScanMetadata() async -> ScanMetadataSnapshot? {
        let context = persistence.viewContext

        return await context.perform {
            guard let metadata = Self.newestMetadata(in: context) else { return nil }
            guard let lastScanDate = metadata.lastScanDate else { return nil }

            return ScanMetadataSnapshot(
                lastScanDate: lastScanDate,
                libraryChangeToken: metadata.photoLibraryChangeToken
                    .flatMap { Data(base64Encoded: $0) },
                imageAssetCount: Int(metadata.totalPhotosScanned)
            )
        }
    }

    public func updateLastScanDate(_ date: Date) async throws {
        try await updateScanMetadata(ScanMetadataSnapshot(lastScanDate: date))
    }

    /// Writes the whole baseline in one save. A partially written baseline —
    /// a date without a fingerprint — is what makes change detection fail open
    /// and prompt for a rescan the app just completed.
    public func updateScanMetadata(_ metadata: ScanMetadataSnapshot?) async throws {
        try await persistence.performBackgroundTask { context in
            let request = ScanMetadataEntity.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \ScanMetadataEntity.lastScanDate, ascending: false)
            ]
            let existing = try context.fetch(request)

            guard let metadata else {
                existing.forEach(context.delete)
                try context.save()
                return
            }

            // Nothing enforces a singleton row, so collapse any duplicates
            // instead of leaving an unsorted fetch to pick one at random.
            let row = existing.first ?? ScanMetadataEntity(context: context)
            existing.dropFirst().forEach(context.delete)

            row.lastScanDate = metadata.lastScanDate
            row.photoLibraryChangeToken = metadata.libraryChangeToken?.base64EncodedString()
            row.totalPhotosScanned = Int32(clamping: metadata.imageAssetCount)
            try context.save()
        }
    }

    public func captureScanMetadata(completedAt: Date) async -> ScanMetadataSnapshot {
        ScanMetadataSnapshot(
            lastScanDate: completedAt,
            libraryChangeToken: changeDetector.currentToken(),
            imageAssetCount: changeDetector.imageAssetCount()
        )
    }

    /// True only when image assets were actually added to or removed from the
    /// library since the last scan.
    public func hasGalleryChanged() async -> Bool {
        guard let metadata = await loadScanMetadata() else {
            AppLog.storage.debug("\(AppLog.tag(.storage, "Gallery change check: no scan baseline"))")
            return true
        }

        guard let token = metadata.libraryChangeToken else {
            // Baseline written before library fingerprinting existed: there is no
            // historical fingerprint to trust, and adopting today's library state
            // as the baseline would silently swallow every change made since the
            // prior-version scan. Require one rescan instead; that scan captures
            // its fingerprint honestly and this branch is never hit again.
            AppLog.storage.debug(
                "\(AppLog.tag(.storage, "Gallery change check: missing change token, requesting one-time rescan"))"
            )
            return true
        }

        guard let summary = changeDetector.changes(since: token) else {
            // Token expired: compare counts instead of assuming a change.
            let currentCount = changeDetector.imageAssetCount()
            let changed = currentCount != metadata.imageAssetCount
            AppLog.storage.debug(
                "\(AppLog.tag(.storage, "Gallery change check: token unusable, count \(metadata.imageAssetCount)->\(currentCount) changed=\(changed)"))"
            )
            return changed
        }

        let changed = summary.insertedImageCount > 0
            || (summary.hasDeletions && changeDetector.imageAssetCount() != metadata.imageAssetCount)
        AppLog.storage.debug(
            "\(AppLog.tag(.storage, "Gallery change check: inserted=\(summary.insertedImageCount) deletions=\(summary.hasDeletions) changed=\(changed)"))"
        )
        return changed
    }

    private static func newestMetadata(in context: NSManagedObjectContext) -> ScanMetadataEntity? {
        let request = ScanMetadataEntity.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ScanMetadataEntity.lastScanDate, ascending: false)
        ]
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    @MainActor
    func saveClusterData(_ clusterData: [ClusterData]) async throws {
        try await persistence.performBackgroundTask { context in
            let start = ContinuousClock().now
            context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
            
            let existingClusters = try context.fetch(ClusterEntity.fetchRequest())
            for cluster in existingClusters {
                let photos = cluster.photos as? Set<PhotoEntity> ?? []
                for photo in photos {
                    photo.cluster = nil
                }
                context.delete(cluster)
            }

            let photoIdentifiers = Array(Set(clusterData.flatMap { $0.assets.map(\.localIdentifier) }))
            var existingPhotosByIdentifier: [String: PhotoEntity] = [:]
            
            if !photoIdentifiers.isEmpty {
                for batch in photoIdentifiers.chunked(into: Constants.maxInPredicateBatchSize) {
                    let request = PhotoEntity.fetchRequest()
                    request.predicate = NSPredicate(
                        format: "localIdentifier IN %@",
                        batch
                    )
                    let photos = try context.fetch(request)
                    for photo in photos {
                        existingPhotosByIdentifier[photo.localIdentifier] = photo
                    }
                }
            }

            for data in clusterData {
                let entity = ClusterEntity(context: context)
                entity.id = data.id
                entity.createdAt = data.createdAt
                entity.averageSimilarity = data.averageSimilarity

                for assetData in data.assets {
                    let photoEntity = existingPhotosByIdentifier[assetData.localIdentifier] ?? {
                        let created = PhotoEntity(context: context)
                        created.localIdentifier = assetData.localIdentifier
                        existingPhotosByIdentifier[assetData.localIdentifier] = created
                        return created
                    }()
                    photoEntity.creationDate = assetData.creationDate
                    photoEntity.modificationDate = assetData.modificationDate
                    photoEntity.pixelWidth = Int32(assetData.pixelWidth)
                    photoEntity.pixelHeight = Int32(assetData.pixelHeight)
                    photoEntity.isFavorite = assetData.isFavorite
                    photoEntity.cluster = entity
                }
            }

            try context.save()
            AppLog.storage.debug("\(AppLog.tag(.storage, "Save clusters count=\(clusterData.count) duration=\(start.duration(to: ContinuousClock().now))"))")
        }
    }

    func loadClusterData() async throws -> [ClusterData] {
        try await persistence.performBackgroundTask { context in
            let request = ClusterEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ClusterEntity.createdAt, ascending: false)]

            let entities = try context.fetch(request)
            return entities.map { entity in
                ClusterData(
                    id: entity.id,
                    createdAt: entity.createdAt,
                    averageSimilarity: entity.averageSimilarity,
                    assets: entity.photosArray.map { photo in
                        AssetData(
                            localIdentifier: photo.localIdentifier,
                            creationDate: photo.creationDate,
                            modificationDate: photo.modificationDate,
                            pixelWidth: Int(photo.pixelWidth),
                            pixelHeight: Int(photo.pixelHeight),
                            isFavorite: photo.isFavorite
                        )
                    }
                )
            }
        }
    }

    @MainActor
    private func makeClusterData(from clusters: [PhotoCluster]) -> [ClusterData] {
        clusters.map { cluster in
            ClusterData(
                id: cluster.id,
                createdAt: cluster.createdAt,
                averageSimilarity: cluster.averageSimilarity,
                assets: cluster.assets.map { asset in
                    AssetData(
                        localIdentifier: asset.localIdentifier,
                        creationDate: asset.creationDate,
                        modificationDate: asset.modificationDate,
                        pixelWidth: asset.pixelWidth,
                        pixelHeight: asset.pixelHeight,
                        isFavorite: asset.isFavorite
                    )
                }
            )
        }
    }
}

// MARK: - Feature Print Cache

extension CoreDataPhotoClusterRepository: PhotoFeaturePrintRepository {
    public func loadFeaturePrints(for localIdentifiers: [String]) async throws -> [String: PhotoFeaturePrintCacheEntry] {
        guard !localIdentifiers.isEmpty else { return [:] }
        
        let context = persistence.viewContext
        return try await context.perform {
            let start = ContinuousClock().now
            let identifiers = Array(Set(localIdentifiers))
            var result: [String: PhotoFeaturePrintCacheEntry] = [:]
            
            for batch in identifiers.chunked(into: Constants.maxInPredicateBatchSize) {
                let request = PhotoEntity.fetchRequest()
                request.predicate = NSPredicate(
                    format: "localIdentifier IN %@ AND featurePrintData != nil",
                    batch
                )
                
                let entities = try context.fetch(request)
                for entity in entities {
                    guard let data = entity.featurePrintData else { continue }
                    result[entity.localIdentifier] = PhotoFeaturePrintCacheEntry(
                        localIdentifier: entity.localIdentifier,
                        modificationDate: entity.modificationDate,
                        featurePrintData: data
                    )
                }
            }
            AppLog.storage.debug(
                "\(AppLog.tag(.storage, "Load feature prints requested=\(identifiers.count) hit=\(result.count) duration=\(start.duration(to: ContinuousClock().now))"))"
            )
            return result
        }
    }
    
    public func upsertFeaturePrints(_ entries: [PhotoFeaturePrintCacheEntry]) async throws {
        guard !entries.isEmpty else { return }
        
        let identifiers = Array(Set(entries.map(\.localIdentifier)))
        try await persistence.performBackgroundTask { context in
            let start = ContinuousClock().now
            context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
            
            var entitiesByIdentifier: [String: PhotoEntity] = [:]
            for batch in identifiers.chunked(into: Constants.maxInPredicateBatchSize) {
                let request = PhotoEntity.fetchRequest()
                request.predicate = NSPredicate(format: "localIdentifier IN %@", batch)
                let existing = try context.fetch(request)
                for entity in existing {
                    entitiesByIdentifier[entity.localIdentifier] = entity
                }
            }
            
            for entry in entries {
                let entity = entitiesByIdentifier[entry.localIdentifier] ?? {
                    let created = PhotoEntity(context: context)
                    created.localIdentifier = entry.localIdentifier
                    entitiesByIdentifier[entry.localIdentifier] = created
                    return created
                }()
                
                entity.featurePrintData = entry.featurePrintData
                entity.modificationDate = entry.modificationDate
            }
            
            try context.save()
            AppLog.storage.debug(
                "\(AppLog.tag(.storage, "Upsert feature prints count=\(entries.count) duration=\(start.duration(to: ContinuousClock().now))"))"
            )
        }
    }
}

// Shared by every repository that batches an `IN` predicate.
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        guard !isEmpty else { return [] }
        
        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)
        
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<end]))
            index = end
        }
        
        return result
    }
}
