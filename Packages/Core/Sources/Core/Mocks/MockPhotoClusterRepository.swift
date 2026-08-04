import Foundation

#if DEBUG

/// Mock implementation of PhotoClusterRepository for SwiftUI previews and unit tests.
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

    /// Library fingerprint the mock hands back from `captureScanMetadata`.
    public var libraryChangeToken: Data? = Data([0xAB])
    public var imageAssetCount = 0
    public private(set) var scanMetadata: ScanMetadataSnapshot?
    public private(set) var scanMetadataWrites: [ScanMetadataSnapshot?] = []
    /// Ordered record of the persistence calls a scan makes, so tests can
    /// assert the scan baseline is written only after clusters are saved.
    public private(set) var persistenceLog: [String] = []
    
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

    public func setDeleteAllClustersResult(_ result: Result<Void, Error>) {
        deleteAllClustersResult = result
    }
    
    public func setGetLastScanDateResult(_ date: Date?) {
        getLastScanDateResult = date
    }

    public func setUpdateLastScanDateResult(_ result: Result<Void, Error>) {
        updateLastScanDateResult = result
    }
    
    public func setLibraryFingerprint(token: Data?, imageAssetCount: Int) {
        libraryChangeToken = token
        self.imageAssetCount = imageAssetCount
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
        persistenceLog.append("saveClusters")
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
        try await updateScanMetadata(ScanMetadataSnapshot(lastScanDate: date))
    }

    public func loadScanMetadata() async -> ScanMetadataSnapshot? {
        didCallGetLastScanDate = true
        if let scanMetadata { return scanMetadata }
        return getLastScanDateResult.map { ScanMetadataSnapshot(lastScanDate: $0) }
    }

    public func updateScanMetadata(_ metadata: ScanMetadataSnapshot?) async throws {
        didCallUpdateLastScanDate = true
        persistenceLog.append("updateScanMetadata")
        scanMetadataWrites.append(metadata)
        switch updateLastScanDateResult {
        case .success:
            scanMetadata = metadata
            getLastScanDateResult = metadata?.lastScanDate
        case .failure(let error):
            throw error
        }
    }

    public func captureScanMetadata(completedAt: Date) async -> ScanMetadataSnapshot {
        ScanMetadataSnapshot(
            lastScanDate: completedAt,
            libraryChangeToken: libraryChangeToken,
            imageAssetCount: imageAssetCount
        )
    }


    public func hasGalleryChanged() async -> Bool {
        didCallHasGalleryChanged = true
        return hasGalleryChangedResult
    }
}

#endif
