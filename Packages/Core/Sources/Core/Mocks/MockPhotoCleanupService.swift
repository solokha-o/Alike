import Foundation

#if DEBUG

public actor MockPhotoCleanupService: PhotoCleanupService {
    public var deleteAssetsResult: Result<CleanupCompletionRecord, Error>
    public var didCallDeleteAssets = false
    public var lastLocalIdentifiers: Set<String>?
    public var lastSourceClusterID: UUID?
    public var lastEstimatedSavingsBytes: Int64?

    public init(
        deleteAssetsResult: Result<CleanupCompletionRecord, Error> = .success(
            CleanupCompletionRecord(
                sourceClusterID: UUID(),
                deletedCount: 1,
                estimatedSavingsBytes: 1
            )
        )
    ) {
        self.deleteAssetsResult = deleteAssetsResult
    }

    public func setDeleteAssetsResult(_ result: Result<CleanupCompletionRecord, Error>) {
        deleteAssetsResult = result
    }

    public func deleteAssets(
        localIdentifiers: Set<String>,
        sourceClusterID: UUID,
        estimatedSavingsBytes: Int64
    ) async throws -> CleanupCompletionRecord {
        didCallDeleteAssets = true
        lastLocalIdentifiers = localIdentifiers
        lastSourceClusterID = sourceClusterID
        lastEstimatedSavingsBytes = estimatedSavingsBytes

        switch deleteAssetsResult {
        case .success(let record):
            return record
        case .failure(let error):
            throw error
        }
    }
}

#endif
