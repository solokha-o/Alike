import CoreData
import Core
import Foundation
import Photos

/// CoreData implementation of PhotoClusterRepository
public final class CoreDataPhotoClusterRepository: PhotoClusterRepository {
    private enum Constants {
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
    
    public init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }
    
    public func loadClusters() async throws -> [PhotoCluster] {
        let context = persistence.viewContext
        
        return try await context.perform {
            let request = ClusterEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ClusterEntity.createdAt, ascending: false)]
            
            let entities = try context.fetch(request)
            
            return entities.compactMap { entity -> PhotoCluster? in
                let localIdentifiers = entity.photosArray.map { $0.localIdentifier }
                
                // Fetch PHAssets from local identifiers
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
                var assets: [PHAsset] = []
                fetchResult.enumerateObjects { asset, _, _ in
                    assets.append(asset)
                }
                
                guard !assets.isEmpty else { return nil }
                
                return PhotoCluster(
                    id: entity.id,
                    assets: assets,
                    createdAt: entity.createdAt,
                    averageSimilarity: entity.averageSimilarity
                )
            }
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
        let context = persistence.viewContext
        
        return await context.perform {
            let request = ScanMetadataEntity.fetchRequest()
            request.fetchLimit = 1
            
            guard let metadata = try? context.fetch(request).first else {
                return nil
            }
            
            return metadata.lastScanDate
        }
    }
    
    public func updateLastScanDate(_ date: Date) async throws {
        try await persistence.performBackgroundTask { context in
            let request = ScanMetadataEntity.fetchRequest()
            let metadata: ScanMetadataEntity
            
            if let existing = try context.fetch(request).first {
                metadata = existing
            } else {
                metadata = ScanMetadataEntity(context: context)
            }
            
            metadata.lastScanDate = date
            try context.save()
        }
    }
    
    public func hasGalleryChanged() async -> Bool {
        guard let lastScanDate = await getLastScanDate() else {
            return true // No previous scan
        }
        
        let context = persistence.viewContext
        
        return await context.perform {
            // Get count of photos modified after last scan
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(
                format: "modificationDate > %@",
                lastScanDate as NSDate
            )
            
            let modifiedPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            return modifiedPhotos.count > 0
        }
    }

    @MainActor
    func saveClusterData(_ clusterData: [ClusterData]) async throws {
        try await persistence.performBackgroundTask { context in
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
        }
    }

    func loadClusterData() async throws -> [ClusterData] {
        let context = persistence.viewContext

        return try await context.perform {
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
            
            return result
        }
    }
    
    public func upsertFeaturePrints(_ entries: [PhotoFeaturePrintCacheEntry]) async throws {
        guard !entries.isEmpty else { return }
        
        let identifiers = Array(Set(entries.map(\.localIdentifier)))
        try await persistence.performBackgroundTask { context in
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
        }
    }
}

private extension Array {
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
