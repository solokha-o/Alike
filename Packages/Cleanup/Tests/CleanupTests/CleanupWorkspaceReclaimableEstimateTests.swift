import Cleanup
import Core
import Photos
import XCTest

/// `ScanSummary.estimatedSavingsBytes`, the cold-launch estimate and the
/// content's own estimate are one figure, computed once: every asset counted
/// once across clusters and categories, and the keeper never counted.
@MainActor
final class CleanupWorkspaceReclaimableEstimateTests: XCTestCase {
    func testScanSummaryCountsAScreenshotInsideAClusterOnce() async throws {
        // 2 000 × 1 000 / 2 = 1 000 000 bytes per asset.
        let keeperCandidateA = FakePhotoAsset(localIdentifier: "a", pixelWidth: 2_000, pixelHeight: 1_000)
        let keeperCandidateB = FakePhotoAsset(localIdentifier: "b", pixelWidth: 2_000, pixelHeight: 1_000)
        let screenshotInCluster = FakePhotoAsset(localIdentifier: "shot", pixelWidth: 2_000, pixelHeight: 1_000)
        let cluster = PhotoCluster(assets: [keeperCandidateA, keeperCandidateB, screenshotInCluster])

        // The real analysis service persists the snapshot and returns its summary;
        // the mock does neither, so the test seeds both halves the same way.
        let screenshots = CleanupCategorySnapshot(
            kind: .screenshots,
            localIdentifiers: ["shot", "other-shot"],
            assetCount: 2,
            estimatedSavingsBytes: 1_000_000 + 250_000
        )
        let analysis = MockPhotoAnalysisService()
        await analysis.setAnalyzePhotoLibraryResult(.success([cluster]))
        await analysis.setRefreshCleanupCategoriesResult(.success([screenshots.summary]))
        let categoryRepository = MockCleanupCategorySnapshotRepository()
        await categoryRepository.setStoredSnapshots([.screenshots: screenshots])
        let workspace = makeWorkspace(analysisService: analysis, categoryRepository: categoryRepository)

        let summary = try await workspace.scan(sensitivity: .medium)

        // Three assets minus the keeper = 2 000 000 from the cluster; the category
        // adds only the screenshot the cluster did not already count.
        let keeper = try XCTUnwrap(cluster.bestShotAsset()?.localIdentifier)
        XCTAssertTrue(["a", "b", "shot"].contains(keeper))
        let expectedClusterBytes: Int64 = 2_000_000
        let expectedCategoryBytes: Int64 = keeper == "shot" ? 1_250_000 : 250_000
        XCTAssertEqual(summary.estimatedSavingsBytes, expectedClusterBytes + expectedCategoryBytes)
        XCTAssertEqual(workspace.reclaimableEstimate.totalBytes, summary.estimatedSavingsBytes)
        XCTAssertEqual(workspace.content?.categorySnapshots.map(\.kind), [.screenshots])
    }

    func testColdLoadExcludesTheUserChosenKeeperAndMatchesContentEstimate() async {
        let first = FakePhotoAsset(localIdentifier: "first", pixelWidth: 2_000, pixelHeight: 1_000)
        let chosen = FakePhotoAsset(localIdentifier: "chosen", pixelWidth: 4_000, pixelHeight: 1_000)
        let third = FakePhotoAsset(localIdentifier: "third", pixelWidth: 2_000, pixelHeight: 500)
        let cluster = PhotoCluster(assets: [first, chosen, third])

        let repository = MockPhotoClusterRepository()
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        await repository.setLoadClustersResult(.success([cluster]))
        let reviewRepository = MockClusterReviewStateRepository()
        await reviewRepository.setStoredStates([
            cluster.id: ClusterReviewState(
                clusterID: cluster.id,
                bestShotLocalIdentifier: "chosen",
                isBestShotUserSelected: true,
                selectedLocalIdentifiers: [],
                status: .inReview,
                estimatedSavingsBytes: 0
            )
        ])
        let categoryRepository = MockCleanupCategorySnapshotRepository()
        await categoryRepository.setStoredSnapshots([
            .blurredPhotos: CleanupCategorySnapshot(
                kind: .blurredPhotos,
                localIdentifiers: ["third", "blurred-only"],
                assetCount: 2,
                estimatedSavingsBytes: 500_000 + 100_000
            )
        ])
        let workspace = makeWorkspace(
            repository: repository,
            reviewRepository: reviewRepository,
            categoryRepository: categoryRepository
        )

        await workspace.loadCachedContent()

        // "chosen" is the user's keeper (2 000 000 bytes, excluded); "first" is
        // 1 000 000 and "third" 500 000; the category adds only "blurred-only".
        XCTAssertEqual(workspace.reclaimableEstimate, ReclaimableEstimate(clusterBytes: 1_500_000, categoryBytes: 100_000))
        XCTAssertEqual(workspace.reclaimableEstimate, workspace.content?.reclaimableEstimate())
        XCTAssertEqual(workspace.cleanupCategories.map(\.estimatedSavingsBytes), [600_000])
    }

    func testCategoryRepositoryFailureLeavesTheClusterHalfOfTheEstimate() async {
        let keep = FakePhotoAsset(localIdentifier: "keep", pixelWidth: 2_000, pixelHeight: 1_000)
        let other = FakePhotoAsset(localIdentifier: "other", pixelWidth: 2_000, pixelHeight: 1_000)
        let cluster = PhotoCluster(assets: [keep, other])
        let repository = MockPhotoClusterRepository()
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        await repository.setLoadClustersResult(.success([cluster]))
        let categoryRepository = MockCleanupCategorySnapshotRepository()
        await categoryRepository.setLoadAllSnapshotsError(CategoryReadFailure())
        let workspace = makeWorkspace(repository: repository, categoryRepository: categoryRepository)

        await workspace.loadCachedContent()

        XCTAssertEqual(workspace.reclaimableEstimate, ReclaimableEstimate(clusterBytes: 1_000_000, categoryBytes: 0))
        XCTAssertEqual(workspace.content?.categorySnapshots, [])
    }

    func testResetClearsTheEstimate() async {
        let cluster = PhotoCluster(assets: [
            FakePhotoAsset(localIdentifier: "keep", pixelWidth: 2_000, pixelHeight: 1_000),
            FakePhotoAsset(localIdentifier: "other", pixelWidth: 2_000, pixelHeight: 1_000)
        ])
        let repository = MockPhotoClusterRepository()
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        await repository.setLoadClustersResult(.success([cluster]))
        let workspace = makeWorkspace(repository: repository)
        await workspace.loadCachedContent()
        XCTAssertNotEqual(workspace.reclaimableEstimate, .zero)

        await workspace.prepareForDataDeletion()

        XCTAssertEqual(workspace.reclaimableEstimate, .zero)
    }

    private func makeWorkspace(
        analysisService: any PhotoAnalysisService = MockPhotoAnalysisService(),
        repository: any PhotoClusterRepository = MockPhotoClusterRepository(),
        reviewRepository: any ClusterReviewStateRepository = MockClusterReviewStateRepository(),
        categoryRepository: any CleanupCategorySnapshotRepository = MockCleanupCategorySnapshotRepository()
    ) -> CleanupWorkspaceModel {
        CleanupWorkspaceModel(
            analysisService: analysisService,
            repository: repository,
            reviewRepository: reviewRepository,
            cleanupCategoryRepository: categoryRepository,
            cleanupSessionRepository: MockCleanupSessionRepository(),
            cleanupHistoryRepository: MockCleanupHistoryRepository()
        )
    }
}

private struct CategoryReadFailure: Error {}
