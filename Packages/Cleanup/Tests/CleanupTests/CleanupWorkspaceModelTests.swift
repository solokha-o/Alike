import Cleanup
import Core
import XCTest

@MainActor
final class CleanupWorkspaceModelTests: XCTestCase {
    func testCachedContentWithoutBaselineIsNeverScanned() async {
        let workspace = makeWorkspace()

        await workspace.loadCachedContent()

        XCTAssertEqual(workspace.contentState, .neverScanned)
        XCTAssertNil(workspace.content)
    }

    func testSuccessfulScanPublishesSummaryAndCompletedEmptyContent() async throws {
        let analysis = MockPhotoAnalysisService()
        let workspace = makeWorkspace(analysisService: analysis)

        let summary = try await workspace.scan(sensitivity: .medium)

        XCTAssertEqual(summary.clusterCount, 0)
        XCTAssertEqual(summary.cleanupCategoryCandidateCount, 0)
        XCTAssertEqual(workspace.lastScanSummary, summary)
        XCTAssertEqual(workspace.lastCompletedScanDate, summary.completedAt)
        XCTAssertEqual(workspace.content?.clusters, [])
        XCTAssertEqual(workspace.scanOperation, .idle)
    }

    func testCachedContentLoadsPersistedCompletedScanDate() async {
        let repository = MockPhotoClusterRepository()
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        await repository.setGetLastScanDateResult(completedAt)
        let workspace = CleanupWorkspaceModel(
            analysisService: MockPhotoAnalysisService(),
            repository: repository,
            reviewRepository: MockClusterReviewStateRepository(),
            cleanupCategoryRepository: MockCleanupCategorySnapshotRepository(),
            cleanupSessionRepository: MockCleanupSessionRepository(),
            cleanupHistoryRepository: MockCleanupHistoryRepository()
        )

        await workspace.loadCachedContent()

        XCTAssertEqual(workspace.lastCompletedScanDate, completedAt)
    }

    func testReviewStatePersistenceFailureDoesNotFailCommittedScan() async throws {
        let workspace = CleanupWorkspaceModel(
            analysisService: MockPhotoAnalysisService(),
            repository: MockPhotoClusterRepository(),
            reviewRepository: FailingReviewStateRepository(),
            cleanupCategoryRepository: MockCleanupCategorySnapshotRepository(),
            cleanupSessionRepository: MockCleanupSessionRepository(),
            cleanupHistoryRepository: MockCleanupHistoryRepository()
        )

        let summary = try await workspace.scan(sensitivity: .medium)

        XCTAssertEqual(summary.clusterCount, 0)
        XCTAssertEqual(workspace.scanOperation, .idle)
        XCTAssertEqual(workspace.contentState, .content(workspace.content!))
    }
}

private extension CleanupWorkspaceModelTests {
    func makeWorkspace(
        analysisService: any PhotoAnalysisService = MockPhotoAnalysisService()
    ) -> CleanupWorkspaceModel {
        CleanupWorkspaceModel(
            analysisService: analysisService,
            repository: MockPhotoClusterRepository(),
            reviewRepository: MockClusterReviewStateRepository(),
            cleanupCategoryRepository: MockCleanupCategorySnapshotRepository(),
            cleanupSessionRepository: MockCleanupSessionRepository(),
            cleanupHistoryRepository: MockCleanupHistoryRepository()
        )
    }
}

private actor FailingReviewStateRepository: ClusterReviewStateRepository {
    func loadReviewState(clusterID: UUID) async throws -> ClusterReviewState? { nil }

    func loadAllReviewStates() async throws -> [UUID: ClusterReviewState] { [:] }

    func saveReviewState(_ state: ClusterReviewState) async throws {}

    func deleteReviewState(clusterID: UUID) async throws {}

    func deleteAllReviewStates() async throws {
        throw ReviewPersistenceError()
    }
}

private struct ReviewPersistenceError: LocalizedError {
    var errorDescription: String? { "Review persistence failed" }
}
