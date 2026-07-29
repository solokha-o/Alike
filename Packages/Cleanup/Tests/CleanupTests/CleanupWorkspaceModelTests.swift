import Cleanup
import Core
import Observation
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

    func testUnchangedReviewReloadDoesNotPublishWorkspaceContent() async {
        let cluster = PhotoCluster(id: UUID(), assets: [])
        let repository = MockPhotoClusterRepository()
        await repository.setLoadClustersResult(.success([cluster]))
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        let reviewRepository = MockClusterReviewStateRepository()
        let workspace = makeWorkspace(
            repository: repository,
            reviewRepository: reviewRepository
        )
        await workspace.loadCachedContent()
        let observation = ObservationChangeFlag()

        withObservationTracking {
            _ = workspace.contentState
        } onChange: {
            observation.recordChange()
        }

        await workspace.reloadReviewState()

        XCTAssertFalse(observation.hasChanged)
    }

    func testChangedReviewReloadPublishesWorkspaceContent() async {
        let cluster = PhotoCluster(id: UUID(), assets: [])
        let repository = MockPhotoClusterRepository()
        await repository.setLoadClustersResult(.success([cluster]))
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        let reviewRepository = MockClusterReviewStateRepository()
        let workspace = makeWorkspace(
            repository: repository,
            reviewRepository: reviewRepository
        )
        await workspace.loadCachedContent()
        let updatedState = ClusterReviewState(
            clusterID: cluster.id,
            bestShotLocalIdentifier: "best-shot",
            selectedLocalIdentifiers: ["selected-photo"],
            status: .inReview,
            estimatedSavingsBytes: 128
        )
        await reviewRepository.setStoredStates([cluster.id: updatedState])
        let observation = ObservationChangeFlag()

        withObservationTracking {
            _ = workspace.contentState
        } onChange: {
            observation.recordChange()
        }

        await workspace.reloadReviewState()

        XCTAssertTrue(observation.hasChanged)
        XCTAssertEqual(workspace.reviewStates[cluster.id], updatedState)
        XCTAssertEqual(workspace.contentState, .content(workspace.content!))
    }
}

private extension CleanupWorkspaceModelTests {
    func makeWorkspace(
        analysisService: any PhotoAnalysisService = MockPhotoAnalysisService(),
        repository: any PhotoClusterRepository = MockPhotoClusterRepository(),
        reviewRepository: any ClusterReviewStateRepository = MockClusterReviewStateRepository()
    ) -> CleanupWorkspaceModel {
        CleanupWorkspaceModel(
            analysisService: analysisService,
            repository: repository,
            reviewRepository: reviewRepository,
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

private final class ObservationChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var hasChanged: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func recordChange() {
        lock.lock()
        storage = true
        lock.unlock()
    }
}
