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

    /// The widget publisher reads `lastScanSummary` before the estimate, so a keeper
    /// change after a scan must reach the summary without a restart.
    func testKeeperChangeAfterScanUpdatesTheScanSummarySavings() async throws {
        // 2 000 000 and 1 000 000 bytes.
        let large = FakePhotoAsset(localIdentifier: "large", pixelWidth: 4_000, pixelHeight: 1_000)
        let small = FakePhotoAsset(localIdentifier: "small", pixelWidth: 2_000, pixelHeight: 1_000)
        let cluster = PhotoCluster(assets: [large, small])
        let analysis = MockPhotoAnalysisService()
        await analysis.setAnalyzePhotoLibraryResult(.success([cluster]))
        let reviewRepository = MockClusterReviewStateRepository()
        let workspace = makeWorkspace(analysisService: analysis, reviewRepository: reviewRepository)

        let scanned = try await workspace.scan(sensitivity: .medium)
        let keeper = try XCTUnwrap(cluster.bestShotAsset()?.localIdentifier)
        let newKeeper = keeper == "large" ? "small" : "large"
        let expectedBytes: Int64 = newKeeper == "large" ? 1_000_000 : 2_000_000
        XCTAssertNotEqual(scanned.estimatedSavingsBytes, expectedBytes)

        await reviewRepository.setStoredStates([
            cluster.id: ClusterReviewState(
                clusterID: cluster.id,
                bestShotLocalIdentifier: newKeeper,
                isBestShotUserSelected: true,
                selectedLocalIdentifiers: [],
                status: .inReview,
                estimatedSavingsBytes: 0
            )
        ])
        await workspace.reloadReviewState()

        XCTAssertEqual(workspace.reclaimableEstimate.totalBytes, expectedBytes)
        XCTAssertEqual(workspace.lastScanSummary, ScanSummary(
            clusterCount: scanned.clusterCount,
            cleanupCategoryCandidateCount: scanned.cleanupCategoryCandidateCount,
            estimatedSavingsBytes: expectedBytes,
            completedAt: scanned.completedAt
        ))
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

    /// A category persisted with the pixel heuristic is re-measured on load and
    /// written back, so its overlap with a cluster is subtracted in one unit.
    func testColdLoadRemeasuresAHeuristicCategoryAndPersistsIt() async throws {
        let repository = MockPhotoClusterRepository()
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        await repository.setLoadClustersResult(.success([]))
        let categoryRepository = MockCleanupCategorySnapshotRepository()
        await categoryRepository.setStoredSnapshots([
            .screenshots: CleanupCategorySnapshot(
                kind: .screenshots,
                localIdentifiers: ["shot", "gone"],
                assetCount: 2,
                estimatedSavingsBytes: 9_999_999,
                byteSizeVersion: nil
            )
        ])
        let workspace = makeWorkspace(
            repository: repository,
            categoryRepository: categoryRepository,
            assetBytesByIdentifier: { identifiers in
                identifiers.contains("shot") ? ["shot": 4_321] : [:]
            }
        )

        await workspace.loadCachedContent()

        XCTAssertEqual(workspace.cleanupCategories.map(\.estimatedSavingsBytes), [4_321])
        XCTAssertEqual(workspace.reclaimableEstimate.categoryBytes, 4_321)
        let storedSnapshots = await categoryRepository.storedSnapshots
        let persisted = try XCTUnwrap(storedSnapshots[.screenshots])
        XCTAssertEqual(persisted.estimatedSavingsBytes, 4_321)
        XCTAssertEqual(persisted.byteSizeVersion, AssetByteSize.currentVersion)
    }

    /// A scan that lands while the launch load is still reading legacy categories
    /// has already stored fresh ones; the load must not write its re-measured
    /// legacy copies over them.
    func testLegacyMigrationDoesNotOverwriteCategoriesStoredByAConcurrentScan() async throws {
        let repository = MockPhotoClusterRepository()
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        await repository.setLoadClustersResult(.success([]))
        let categoryRepository = MockCleanupCategorySnapshotRepository()
        await categoryRepository.setStoredSnapshots([
            .screenshots: CleanupCategorySnapshot(
                kind: .screenshots,
                localIdentifiers: ["old"],
                assetCount: 1,
                estimatedSavingsBytes: 9_999_999,
                refreshedAt: Date(timeIntervalSince1970: 1),
                byteSizeVersion: nil
            )
        ])
        let analysisService = MockPhotoAnalysisService()
        await analysisService.setRefreshCleanupCategoriesResult(.success([
            CleanupCategorySummary(kind: .screenshots, assetCount: 1, estimatedSavingsBytes: 7)
        ]))
        let workspace = makeWorkspace(
            analysisService: analysisService,
            repository: repository,
            categoryRepository: categoryRepository,
            assetBytesByIdentifier: { _ in ["old": 4_321] }
        )

        await categoryRepository.suspendNextLoadAllSnapshots()
        let load = Task { await workspace.loadCachedContent() }
        while await !categoryRepository.isLoadAllSnapshotsSuspended {
            await Task.yield()
        }

        // The scan's refresh stores current categories while the load is paused.
        let fresh = CleanupCategorySnapshot(
            kind: .screenshots,
            localIdentifiers: ["new"],
            assetCount: 1,
            estimatedSavingsBytes: 7,
            refreshedAt: Date(timeIntervalSince1970: 2)
        )
        await categoryRepository.setStoredSnapshots([.screenshots: fresh])
        _ = try await workspace.scan(sensitivity: .medium)

        await categoryRepository.resumeLoadAllSnapshots()
        await load.value

        let storedSnapshots = await categoryRepository.storedSnapshots
        XCTAssertEqual(storedSnapshots[.screenshots], fresh)
        XCTAssertEqual(workspace.cleanupCategories.map(\.estimatedSavingsBytes), [7])
    }

    /// The first launch on a library with categories but no clusters measures
    /// only during the legacy migration; those sizes still reach the store, so
    /// opening a category later does not ask PhotoKit again.
    func testFirstLegacyLoadWithoutClustersPersistsTheMeasuredSizes() async throws {
        let repository = MockPhotoClusterRepository()
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        await repository.setLoadClustersResult(.success([]))
        let identifier = "shot-\(UUID().uuidString)"
        let categoryRepository = MockCleanupCategorySnapshotRepository()
        await categoryRepository.setStoredSnapshots([
            .screenshots: CleanupCategorySnapshot(
                kind: .screenshots,
                localIdentifiers: [identifier],
                assetCount: 1,
                estimatedSavingsBytes: 9_999_999,
                byteSizeVersion: nil
            )
        ])
        let byteSizeRepository = MockAssetByteSizeRepository()
        let measured = AssetByteSizeRecord(localIdentifier: identifier, modificationDate: nil, bytes: 4_321)
        let workspace = makeWorkspace(
            repository: repository,
            categoryRepository: categoryRepository,
            byteSizeRepository: byteSizeRepository,
            assetBytesByIdentifier: { identifiers in
                guard identifiers.contains(identifier) else { return [:] }
                AssetByteSize.record(measured)
                return [identifier: measured.bytes]
            }
        )

        await workspace.loadCachedContent()

        let saveCount = await byteSizeRepository.replaceAllCallCount
        let storedRecords = await byteSizeRepository.storedRecords
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(storedRecords, [measured])
    }

    func testColdLoadRemeasuresAHeuristicReviewStateAndPersistsIt() async throws {
        let keeper = FakePhotoAsset(localIdentifier: "keeper", pixelWidth: 4_000, pixelHeight: 1_000)
        let selected = FakePhotoAsset(localIdentifier: "selected", pixelWidth: 2_000, pixelHeight: 1_000)
        let cluster = PhotoCluster(assets: [keeper, selected])
        let repository = MockPhotoClusterRepository()
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        await repository.setLoadClustersResult(.success([cluster]))
        let reviewRepository = MockClusterReviewStateRepository()
        await reviewRepository.setStoredStates([
            cluster.id: ClusterReviewState(
                clusterID: cluster.id,
                bestShotLocalIdentifier: "keeper",
                selectedLocalIdentifiers: ["selected"],
                status: .reviewed,
                estimatedSavingsBytes: 1,
                byteSizeVersion: nil
            )
        ])
        let workspace = makeWorkspace(repository: repository, reviewRepository: reviewRepository)

        await workspace.loadCachedContent()

        // Fake assets have no PhotoKit resources, so the source falls back to 2 000 × 1 000 / 2.
        XCTAssertEqual(workspace.reviewState(for: cluster.id)?.estimatedSavingsBytes, 1_000_000)
        let storedStates = await reviewRepository.storedStates
        let persisted = try XCTUnwrap(storedStates[cluster.id])
        XCTAssertEqual(persisted.estimatedSavingsBytes, 1_000_000)
        XCTAssertEqual(persisted.byteSizeVersion, AssetByteSize.currentVersion)
    }

    /// The size store is read once per workspace — a scan after the launch load
    /// reuses it — and is not rewritten when nothing new was measured.
    func testColdLoadSeedsByteSizesOnceAndSkipsAnUnchangedSave() async throws {
        let repository = MockPhotoClusterRepository()
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        await repository.setLoadClustersResult(.success([
            PhotoCluster(assets: [FakePhotoAsset(localIdentifier: "a"), FakePhotoAsset(localIdentifier: "b")])
        ]))
        let byteSizeRepository = MockAssetByteSizeRepository()
        let workspace = makeWorkspace(repository: repository, byteSizeRepository: byteSizeRepository)

        await workspace.loadCachedContent()
        _ = try await workspace.scan(sensitivity: .medium)

        let loadCount = await byteSizeRepository.loadAllCallCount
        let saveCount = await byteSizeRepository.replaceAllCallCount
        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(saveCount, 0)
    }

    private func makeWorkspace(
        analysisService: any PhotoAnalysisService = MockPhotoAnalysisService(),
        repository: any PhotoClusterRepository = MockPhotoClusterRepository(),
        reviewRepository: any ClusterReviewStateRepository = MockClusterReviewStateRepository(),
        categoryRepository: any CleanupCategorySnapshotRepository = MockCleanupCategorySnapshotRepository(),
        byteSizeRepository: any AssetByteSizeRepository = MockAssetByteSizeRepository(),
        assetBytesByIdentifier: @escaping @Sendable ([String]) -> [String: Int64] = { _ in [:] }
    ) -> CleanupWorkspaceModel {
        CleanupWorkspaceModel(
            analysisService: analysisService,
            repository: repository,
            reviewRepository: reviewRepository,
            cleanupCategoryRepository: categoryRepository,
            cleanupSessionRepository: MockCleanupSessionRepository(),
            cleanupHistoryRepository: MockCleanupHistoryRepository(),
            assetByteSizeRepository: byteSizeRepository,
            assetBytesByIdentifier: assetBytesByIdentifier
        )
    }
}

private struct CategoryReadFailure: Error {}
