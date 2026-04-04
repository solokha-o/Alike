import Foundation
import Photos

#if DEBUG

/// Mock implementation of PhotoAnalysisService for SwiftUI previews and unit tests.
public actor MockPhotoAnalysisService: PhotoAnalysisService {
    public var analyzePhotoLibraryResult: Result<[PhotoCluster], Error> = .success([])
    public var calculateSimilarityResult: Result<Float, Error> = .success(0.95)
    public var didCallAnalyzePhotoLibrary = false
    public var didCallCalculateSimilarity = false
    public var lastSensitivity: Float?
    public var lastProgressCallback: ((Double) -> Void)?
    
    public init() {}
    
    // Setters for test configuration
    public func setAnalyzePhotoLibraryResult(_ result: Result<[PhotoCluster], Error>) {
        analyzePhotoLibraryResult = result
    }
    
    public func setCalculateSimilarityResult(_ result: Result<Float, Error>) {
        calculateSimilarityResult = result
    }
    
    public func analyzePhotoLibrary(
        sensitivity: Float,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [PhotoCluster] {
        didCallAnalyzePhotoLibrary = true
        lastSensitivity = sensitivity
        lastProgressCallback = progress
        
        // Simulate progress
        await MainActor.run {
            progress(0.5)
        }
        await MainActor.run {
            progress(1.0)
        }
        
        switch analyzePhotoLibraryResult {
        case .success(let clusters):
            return clusters
        case .failure(let error):
            throw error
        }
    }
    
    public func calculateSimilarity(asset1: PHAsset, asset2: PHAsset) async throws -> Float {
        didCallCalculateSimilarity = true
        
        switch calculateSimilarityResult {
        case .success(let similarity):
            return similarity
        case .failure(let error):
            throw error
        }
    }
}

#endif
