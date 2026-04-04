import Foundation

#if DEBUG

/// Mock реалізація PhotoClusterRepository для SwiftUI previews та Unit tests
public actor MockPhotoClusterRepository: PhotoClusterRepository {
    public var savedClusters: [PhotoCluster] = []
    public var loadClustersResult: Result<[PhotoCluster], Error> = .success([])
    public var loadClusterSnapshotsResult: Result<[PhotoClusterSnapshot], Error> = .success([])
    public var saveClustersResult: Result<Void, Error> = .success(())
    public var deleteAllClustersResult: Result<Void, Error> = .success(())
    public var getLastScanDateResult: Date?
    public var updateLastScanDateResult: Result<Void, Error> = .success(())
    public var hasGalleryChangedResult = false
    
    public var didCallSaveClusters = false
    public var didCallLoadClusters = false
    public var didCallLoadClusterSnapshots = false
    public var didCallDeleteAllClusters = false
    public var didCallGetLastScanDate = false
    public var didCallUpdateLastScanDate = false
    public var didCallHasGalleryChanged = false
    
    public init() {}
    
    // Setters for test configuration
    public func setLoadClustersResult(_ result: Result<[PhotoCluster], Error>) {
        loadClustersResult = result
    }
    
    public func setSaveClustersResult(_ result: Result<Void, Error>) {
        saveClustersResult = result
    }

    public func setLoadClusterSnapshotsResult(_ result: Result<[PhotoClusterSnapshot], Error>) {
        loadClusterSnapshotsResult = result
    }
    
    public func setGetLastScanDateResult(_ date: Date?) {
        getLastScanDateResult = date
    }
    
    public func setHasGalleryChangedResult(_ changed: Bool) {
        hasGalleryChangedResult = changed
    }
    
    public func loadClusters() async throws -> [PhotoCluster] {
        didCallLoadClusters = true
        switch loadClustersResult {
        case .success(let clusters):
            return clusters
        case .failure(let error):
            throw error
        }
    }

    public func loadClusterSnapshots() async throws -> [PhotoClusterSnapshot] {
        didCallLoadClusterSnapshots = true
        switch loadClusterSnapshotsResult {
        case .success(let snapshots):
            return snapshots
        case .failure(let error):
            throw error
        }
    }
    
    public func saveClusters(_ clusters: [PhotoCluster]) async throws {
        didCallSaveClusters = true
        switch saveClustersResult {
        case .success:
            savedClusters = clusters
        case .failure(let error):
            throw error
        }
    }
    
    public func deleteAllClusters() async throws {
        didCallDeleteAllClusters = true
        switch deleteAllClustersResult {
        case .success:
            savedClusters.removeAll()
        case .failure(let error):
            throw error
        }
    }
    
    public func getLastScanDate() async -> Date? {
        didCallGetLastScanDate = true
        return getLastScanDateResult
    }
    
    public func updateLastScanDate(_ date: Date) async throws {
        didCallUpdateLastScanDate = true
        switch updateLastScanDateResult {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
    
    public func hasGalleryChanged() async -> Bool {
        didCallHasGalleryChanged = true
        return hasGalleryChangedResult
    }
}

#endif
