import Foundation
import Photos

#if DEBUG

/// Mock implementation of PhotoAnalysisService for SwiftUI previews and unit tests.
public actor MockPhotoAnalysisService: PhotoAnalysisService {
    public var analyzePhotoLibraryResult: Result<[PhotoCluster], Error> = .success([])
    public var summarizeCleanupCategoriesResult: Result<[CleanupCategorySummary], Error> = .success([])
    public var refreshCleanupCategoriesResult: Result<[CleanupCategorySummary], Error> = .success([])
    public var loadAssetsResult: Result<[PHAsset], Error> = .success([])
    public var calculateSimilarityResult: Result<Float, Error> = .success(0.95)
    public var didCallAnalyzePhotoLibrary = false
    public var didCallSummarizeCleanupCategories = false
    public var didCallRefreshCleanupCategories = false
    public var didCallLoadAssets = false
    public var didCallCalculateSimilarity = false
    public var lastSensitivity: Float?
    public var lastLoadedCategory: CleanupCategoryKind?
    public var lastProgressCallback: ((Double) -> Void)?
    public var lastCleanupCategoryProgressCallback: ((Double) -> Void)?
    
    public init() {}
    
    // Setters for test configuration
    public func setAnalyzePhotoLibraryResult(_ result: Result<[PhotoCluster], Error>) {
        analyzePhotoLibraryResult = result
    }
    
    public func setCalculateSimilarityResult(_ result: Result<Float, Error>) {
        calculateSimilarityResult = result
    }

    public func setSummarizeCleanupCategoriesResult(_ result: Result<[CleanupCategorySummary], Error>) {
        summarizeCleanupCategoriesResult = result
    }

    public func setLoadAssetsResult(_ result: Result<[PHAsset], Error>) {
        loadAssetsResult = result
    }

    public func setRefreshCleanupCategoriesResult(_ result: Result<[CleanupCategorySummary], Error>) {
        refreshCleanupCategoriesResult = result
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

    public func summarizeCleanupCategories() async throws -> [CleanupCategorySummary] {
        didCallSummarizeCleanupCategories = true

        switch summarizeCleanupCategoriesResult {
        case .success(let summaries):
            return summaries
        case .failure(let error):
            throw error
        }
    }

    public func refreshCleanupCategories(
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [CleanupCategorySummary] {
        didCallRefreshCleanupCategories = true
        lastCleanupCategoryProgressCallback = progress
        progress(0)
        progress(1)

        switch refreshCleanupCategoriesResult {
        case .success(let summaries):
            return summaries
        case .failure(let error):
            throw error
        }
    }

    public func loadAssets(for category: CleanupCategoryKind) async throws -> [PHAsset] {
        didCallLoadAssets = true
        lastLoadedCategory = category

        switch loadAssetsResult {
        case .success(let assets):
            return assets
        case .failure(let error):
            throw error
        }
    }
}

#endif
