import Foundation
import Photos

/// Repository for managing photo clusters
public protocol PhotoClusterRepository: Sendable {
    /// Load all saved clusters
    func loadClusters() async throws -> [PhotoCluster]
    
    /// Save clusters to persistent storage
    func saveClusters(_ clusters: [PhotoCluster]) async throws
    
    /// Delete all clusters
    func deleteAllClusters() async throws
    
    /// Get the timestamp of the last scan
    func getLastScanDate() async -> Date?
    
    /// Update the last scan timestamp
    func updateLastScanDate(_ date: Date) async throws
    
    /// Check if gallery has changed since last scan
    func hasGalleryChanged() async -> Bool
}

/// Repository for cleanup review state per photo cluster.
public protocol ClusterReviewStateRepository: Sendable {
    /// Load review state for a cluster.
    func loadReviewState(clusterID: UUID) async throws -> ClusterReviewState?

    /// Load all review states keyed by cluster id.
    func loadAllReviewStates() async throws -> [UUID: ClusterReviewState]

    /// Save or overwrite review state.
    func saveReviewState(_ state: ClusterReviewState) async throws

    /// Delete one review state.
    func deleteReviewState(clusterID: UUID) async throws

    /// Delete all stored review states.
    func deleteAllReviewStates() async throws
}

/// Service for analyzing photos using Vision framework
public protocol PhotoAnalysisService: Sendable {
    /// Analyze all photos in the library and return clusters
    func analyzePhotoLibrary(sensitivity: Float, progress: @Sendable @escaping (Double) -> Void) async throws -> [PhotoCluster]
    
    /// Calculate similarity between two assets
    func calculateSimilarity(asset1: PHAsset, asset2: PHAsset) async throws -> Float
}

/// Manager for photo library permissions
@MainActor
public protocol PhotoPermissionManager: Sendable {
    /// Current authorization status
    var authorizationStatus: PHAuthorizationStatus { get }
    
    /// Request photo library access
    func requestAuthorization() async -> PHAuthorizationStatus
    
    /// Check if authorization is granted
    var isAuthorized: Bool { get }
    
    /// Open iOS Settings app
    func openSettings()
}
