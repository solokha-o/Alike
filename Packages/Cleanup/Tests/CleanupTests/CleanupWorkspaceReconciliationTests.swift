import Cleanup
import Core
import Photos
import XCTest

/// The post-cleanup refresh. `CleanupWorkspaceBehaviorTests` already covers the
/// two failure shapes — a reconciliation that throws, and a superseded queue —
/// so this covers what reconciliation is actually for: after photos are
/// deleted, the workspace reflects the deletion.
@MainActor
final class CleanupWorkspaceReconciliationTests: XCTestCase {
    func testSuccessfulReconciliationRefreshesClustersCategoriesAndInsights() async {
        let survivingCluster = PhotoCluster(id: UUID(), assets: [])
        let analysis = MockPhotoAnalysisService()
        await analysis.setAnalyzePhotoLibraryResult(.success([survivingCluster]))
        await analysis.setRefreshCleanupCategoriesResult(.success([
            CleanupCategorySummary(kind: .screenshots, assetCount: 2, estimatedSavingsBytes: 200)
        ]))

        // The deletion flow appends the record before asking for a refresh, so
        // the history the refresh reads already contains it.
        let record = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 4,
            estimatedSavingsBytes: 4_096,
            completedAt: Date(timeIntervalSince1970: 5_000)
        )
        let historyRepository = MockCleanupHistoryRepository()
        try? await historyRepository.append(record)

        let workspace = makeWorkspace(
            analysisService: analysis,
            historyRepository: historyRepository
        )

        await workspace.reconcile(after: record, sensitivity: .medium)

        XCTAssertEqual(workspace.reconciliationState, .success(record))
        XCTAssertEqual(workspace.clusters, [survivingCluster])
        XCTAssertEqual(workspace.cleanupCategories.map(\.kind), [.screenshots])
        XCTAssertEqual(workspace.cleanupCategories.first?.assetCount, 2)
        XCTAssertEqual(workspace.cleanupInsights.totalDeletedItems, 4)
        XCTAssertEqual(workspace.cleanupInsights.totalSavedBytes, 4_096)
        XCTAssertEqual(workspace.cleanupInsights.latestCleanup, record)
        XCTAssertTrue(workspace.hasCompletedScanBaseline)
    }

    func testReconciliationLeavesNoScanInFlightSoTheNextOneCanRun() async {
        let analysis = MockPhotoAnalysisService()
        let workspace = makeWorkspace(analysisService: analysis)
        let record = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 1,
            estimatedSavingsBytes: 128,
            completedAt: Date(timeIntervalSince1970: 6_000)
        )

        await workspace.reconcile(after: record, sensitivity: .medium)

        XCTAssertEqual(workspace.scanOperation, .idle)

        // A second reconciliation must run its own scan rather than be swallowed
        // as a duplicate of the first — the queue is drained, not merely idle.
        let secondCluster = PhotoCluster(id: UUID(), assets: [])
        await analysis.setAnalyzePhotoLibraryResult(.success([secondCluster]))
        let secondRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 2,
            estimatedSavingsBytes: 256,
            completedAt: Date(timeIntervalSince1970: 7_000)
        )

        await workspace.reconcile(after: secondRecord, sensitivity: .medium)

        XCTAssertEqual(workspace.reconciliationState, .success(secondRecord))
        XCTAssertEqual(workspace.clusters, [secondCluster])
    }

    private func makeWorkspace(
        analysisService: any PhotoAnalysisService = MockPhotoAnalysisService(),
        historyRepository: any CleanupHistoryRepository = MockCleanupHistoryRepository()
    ) -> CleanupWorkspaceModel {
        CleanupWorkspaceModel(
            analysisService: analysisService,
            repository: MockPhotoClusterRepository(),
            reviewRepository: MockClusterReviewStateRepository(),
            cleanupCategoryRepository: MockCleanupCategorySnapshotRepository(),
            cleanupSessionRepository: MockCleanupSessionRepository(),
            cleanupHistoryRepository: historyRepository
        )
    }
}
