import Foundation
@preconcurrency import Photos
@preconcurrency import Vision
import Core

/// Main photo analysis service that coordinates Vision analysis and clustering
public actor PhotoAnalysisServiceImpl: PhotoAnalysisService {
    private let visionService: any VisionFeaturePrintServicing
    private let clusteringService: any PhotoClusteringServicing
    private let featurePrintRepository: (any PhotoFeaturePrintRepository)?
    private let cleanupCategoryRepository: (any CleanupCategorySnapshotRepository)?
    private let blurAnalysisService: BlurAnalysisService
    private let assetsProvider: @MainActor @Sendable () -> [PHAsset]
    
    public init(
        visionService: VisionFeaturePrintService = VisionFeaturePrintService(),
        clusteringService: PhotoClusteringService = PhotoClusteringService(),
        featurePrintRepository: (any PhotoFeaturePrintRepository)? = nil,
        cleanupCategoryRepository: (any CleanupCategorySnapshotRepository)? = nil
    ) {
        self.init(
            visionService: visionService,
            clusteringService: clusteringService,
            featurePrintRepository: featurePrintRepository,
            cleanupCategoryRepository: cleanupCategoryRepository,
            blurAnalysisService: BlurAnalysisService(),
            assetsProvider: PhotoAnalysisServiceImpl.fetchAllPhotoAssets
        )
    }

    init(
        visionService: any VisionFeaturePrintServicing,
        clusteringService: any PhotoClusteringServicing,
        featurePrintRepository: (any PhotoFeaturePrintRepository)? = nil,
        cleanupCategoryRepository: (any CleanupCategorySnapshotRepository)? = nil,
        blurAnalysisService: BlurAnalysisService = BlurAnalysisService(),
        assetsProvider: @escaping @MainActor @Sendable () -> [PHAsset]
    ) {
        self.visionService = visionService
        self.clusteringService = clusteringService
        self.featurePrintRepository = featurePrintRepository
        self.cleanupCategoryRepository = cleanupCategoryRepository
        self.blurAnalysisService = blurAnalysisService
        self.assetsProvider = assetsProvider
    }
    
    /// Analyze entire photo library and return clusters
    public func analyzePhotoLibrary(
        sensitivity: Float,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [PhotoCluster] {
        try Task.checkCancellation()
        let startTime = ContinuousClock().now

        // Fetch all photo assets
        let assets = await MainActor.run { assetsProvider() }
        
        guard !assets.isEmpty else {
            throw PhotoAnalysisError.noPhotosFound
        }

        let assetsToCluster = assets.filter { !$0.mediaSubtypes.contains(.photoScreenshot) }

        guard !assetsToCluster.isEmpty else {
            progress(1.0)
            return []
        }

        progress(0.01)
        await Task.yield()

        try Task.checkCancellation()

        let cachedFeaturePrints = await loadCachedFeaturePrints(for: assetsToCluster)
        let assetsNeedingComputation = assetsToCluster.filter { cachedFeaturePrints[$0.localIdentifier] == nil }
        let cachedCount = cachedFeaturePrints.count
        AppLog.scan.debug(
            "\(AppLog.tag(.cache, "Assets: \(assetsToCluster.count), cached: \(cachedCount), toCompute: \(assetsNeedingComputation.count)"))"
        )

        if cachedCount > 0 {
            progress((Double(cachedCount) / Double(assetsToCluster.count)) * 0.8)
        }

        // Generate missing feature prints (0-80% of progress)
        let computed = try await visionService.generateFeaturePrints(
            for: assetsNeedingComputation
        ) { computedProgress in
            let completed = Double(cachedCount) + (computedProgress * Double(assetsNeedingComputation.count))
            let overallProgress = (completed / Double(assetsToCluster.count)) * 0.8
            progress(overallProgress)
        }
        let computedSuccessCount = computed.reduce(into: 0) { partialResult, result in
            if result.featurePrint != nil {
                partialResult += 1
            }
        }
        let skippedCount = computed.count - computedSuccessCount
        AppLog.scan.debug(
            "\(AppLog.tag(.vision, "Computed feature prints success=\(computedSuccessCount) attempted=\(computed.count) skipped=\(skippedCount)"))"
        )

        await saveFeaturePrintCache(for: computed)

        let computedByIdentifier = Dictionary(
            uniqueKeysWithValues: computed.compactMap { result -> (String, VNFeaturePrintObservation)? in
                guard let featurePrint = result.featurePrint else { return nil }
                return (result.asset.localIdentifier, featurePrint)
            }
        )

        let photosWithFeaturePrints: [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)] = assetsToCluster.map { asset in
            let featurePrint = cachedFeaturePrints[asset.localIdentifier] ?? computedByIdentifier[asset.localIdentifier]
            return (asset: asset, featurePrint: featurePrint)
        }

        // Perform clustering (80-100% of progress)
        progress(0.8)
        try Task.checkCancellation()
        let clusters = try clusteringService.clusterPhotos(
            photosWithFeaturePrints,
            threshold: sensitivity
        )
        let duration = startTime.duration(to: ContinuousClock().now)
        AppLog.scan.info("\(AppLog.tag(.finish, "Clustering done. clusters=\(clusters.count) duration=\(duration)"))")
        
        progress(1.0)
        
        return clusters
    }

    public func summarizeCleanupCategories() async throws -> [CleanupCategorySummary] {
        guard let cleanupCategoryRepository else { return [] }
        let snapshots = try await cleanupCategoryRepository.loadAllSnapshots()
        return CleanupCategorySummaryBuilder.summaries(
            from: CleanupCategoryKind.allCases.compactMap { snapshots[$0] }
        )
    }

    public func refreshCleanupCategories() async throws -> [CleanupCategorySummary] {
        let assets = await MainActor.run { assetsProvider() }
        let snapshots = try await buildCleanupCategorySnapshots(from: assets)

        if let cleanupCategoryRepository {
            try await cleanupCategoryRepository.deleteAllSnapshots()
            for snapshot in snapshots {
                try await cleanupCategoryRepository.saveSnapshot(snapshot)
            }
        }

        return CleanupCategorySummaryBuilder.summaries(from: snapshots)
    }

    public func loadAssets(for category: CleanupCategoryKind) async throws -> [PHAsset] {
        let assets = await MainActor.run { assetsProvider() }
        let byIdentifier = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })

        if let cleanupCategoryRepository,
           let snapshot = try await cleanupCategoryRepository.loadSnapshot(for: category) {
            let resolved = snapshot.localIdentifiers.compactMap { byIdentifier[$0] }
            if !resolved.isEmpty {
                return resolved
            }
        }

        switch category {
        case .screenshots:
            return assets.filter { $0.mediaSubtypes.contains(.photoScreenshot) }
        case .blurredPhotos:
            return []
        }
    }
    
    /// Calculate similarity between two specific assets
    public func calculateSimilarity(asset1: PHAsset, asset2: PHAsset) async throws -> Float {
        guard let featurePrint1 = try await visionService.generateFeaturePrint(for: asset1),
              let featurePrint2 = try await visionService.generateFeaturePrint(for: asset2) else {
            return 0.0
        }
        
        let distance = try visionService.computeDistance(
            between: featurePrint1,
            and: featurePrint2
        )
        
        // Convert distance to similarity (0-1, where 1 is most similar)
        return max(0.0, min(1.0, 1.0 - (distance / 100.0)))
    }
    
    // MARK: - Private Helpers
    
    @MainActor
    private static func fetchAllPhotoAssets() -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]

        // Only fetch images (not videos)
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        return assets
    }
    
}

private extension PhotoAnalysisServiceImpl {
    func buildCleanupCategorySnapshots(from assets: [PHAsset]) async throws -> [CleanupCategorySnapshot] {
        let assetSnapshots = assets.map(CleanupCategoryAssetSnapshot.init)
        var snapshots: [CleanupCategorySnapshot] = []

        if let screenshotSnapshot = CleanupCategorySummaryBuilder.screenshotSnapshot(from: assetSnapshots) {
            snapshots.append(screenshotSnapshot)
        }

        if let blurSnapshot = try await blurAnalysisService.makeSnapshot(from: assets) {
            snapshots.append(blurSnapshot)
        }

        return snapshots
    }

    func loadCachedFeaturePrints(for assets: [PHAsset]) async -> [String: VNFeaturePrintObservation] {
        guard let featurePrintRepository else { return [:] }

        let identifiers = assets.map(\.localIdentifier)
        guard let cachedEntries = try? await featurePrintRepository.loadFeaturePrints(for: identifiers) else {
            return [:]
        }

        var cachedFeaturePrints: [String: VNFeaturePrintObservation] = [:]
        cachedFeaturePrints.reserveCapacity(cachedEntries.count)

        for asset in assets {
            guard let entry = cachedEntries[asset.localIdentifier] else { continue }
            guard Self.isCacheValid(
                cachedModificationDate: entry.modificationDate,
                assetModificationDate: asset.modificationDate
            ) else { continue }

            guard let featurePrint = decodeFeaturePrint(from: entry.featurePrintData) else { continue }
            cachedFeaturePrints[asset.localIdentifier] = featurePrint
        }

        return cachedFeaturePrints
    }

    func saveFeaturePrintCache(for results: [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)]) async {
        guard let featurePrintRepository else { return }

        let entries: [PhotoFeaturePrintCacheEntry] = results.compactMap { item in
            guard let featurePrint = item.featurePrint,
                  let data = encodeFeaturePrint(featurePrint) else {
                return nil
            }

            return PhotoFeaturePrintCacheEntry(
                localIdentifier: item.asset.localIdentifier,
                modificationDate: item.asset.modificationDate,
                featurePrintData: data
            )
        }

        guard !entries.isEmpty else { return }
        try? await featurePrintRepository.upsertFeaturePrints(entries)
    }

    nonisolated static func isCacheValid(
        cachedModificationDate: Date?,
        assetModificationDate: Date?
    ) -> Bool {
        switch (cachedModificationDate, assetModificationDate) {
        case (nil, nil):
            return true
        case (let cached?, let asset?):
            return abs(cached.timeIntervalSince1970 - asset.timeIntervalSince1970) < 1
        default:
            return false
        }
    }

    func decodeFeaturePrint(from data: Data) -> VNFeaturePrintObservation? {
        do {
            return try NSKeyedUnarchiver.unarchivedObject(
                ofClass: VNFeaturePrintObservation.self,
                from: data
            )
        } catch {
            return nil
        }
    }

    func encodeFeaturePrint(_ observation: VNFeaturePrintObservation) -> Data? {
        do {
            return try NSKeyedArchiver.archivedData(
                withRootObject: observation,
                requiringSecureCoding: true
            )
        } catch {
            return nil
        }
    }
}
