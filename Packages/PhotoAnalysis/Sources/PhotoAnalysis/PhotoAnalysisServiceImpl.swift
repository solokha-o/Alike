import Photos
import Vision
import Core

/// Main photo analysis service that coordinates Vision analysis and clustering
public actor PhotoAnalysisServiceImpl: PhotoAnalysisService {
    private let visionService: VisionFeaturePrintService
    private let clusteringService: PhotoClusteringService
    
    public init(
        visionService: VisionFeaturePrintService = VisionFeaturePrintService(),
        clusteringService: PhotoClusteringService = PhotoClusteringService()
    ) {
        self.visionService = visionService
        self.clusteringService = clusteringService
    }
    
    /// Analyze entire photo library and return clusters
    public func analyzePhotoLibrary(
        sensitivity: Float,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [PhotoCluster] {
        // Fetch all photo assets
        let assets = await MainActor.run {
            fetchAllPhotoAssets()
        }
        
        guard !assets.isEmpty else {
            return []
        }
        
        // Generate feature prints (0-80% of progress)
        let photosWithFeaturePrints = try await visionService.generateFeaturePrints(
            for: assets
        ) { featurePrintProgress in
            let overallProgress = featurePrintProgress * 0.8
            progress(overallProgress)
        }
        
        // Perform clustering (80-100% of progress)
        progress(0.8)
        let clusters = try await clusteringService.clusterPhotos(
            photosWithFeaturePrints,
            threshold: sensitivity
        )
        
        progress(1.0)
        
        return clusters
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
    private func fetchAllPhotoAssets() -> [PHAsset] {
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
