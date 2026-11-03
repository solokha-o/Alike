import XCTest
import Core
import Photos
@testable import Details

@MainActor
final class ClusterDetailsViewModelTests: XCTestCase, ClusterDetailsViewModelFixture {
    let repository = MockClusterReviewStateRepository()
    let cleanupService = MockPhotoCleanupService()
    let cleanupHistoryRepository = MockCleanupHistoryRepository()
    let clusterID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

    func testLoadWithoutPersistedStateComputesBestShot() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "a", isFavorite: false, area: 800, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "b", isFavorite: true, area: 200, createdAt: Date(timeIntervalSince1970: 1))
            ]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "b")
        XCTAssertTrue(viewModel.selectedAssetIDs.isEmpty)
        XCTAssertEqual(viewModel.reviewStatus, .notReviewed)
    }

    func testLoadKeepsComparisonVisibleForUnreviewedCluster() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "candidate", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        XCTAssertFalse(viewModel.hasLoadedReviewState)
        XCTAssertFalse(viewModel.isBestShotCelebrationVisible)

        await viewModel.load()

        XCTAssertTrue(viewModel.hasLoadedReviewState)
        XCTAssertFalse(viewModel.isBestShotCelebrationVisible)
    }

    func testLoadDoesNotShowBestShotCelebrationForSingleAsset() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "only", isFavorite: true, area: 100, createdAt: nil)
            ]
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.hasLoadedReviewState)
        XCTAssertFalse(viewModel.isBestShotCelebrationVisible)
    }

    func testInitializationDefersAssetSnapshotPreparationUntilLoad() async {
        let expectedSnapshots = [
            snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
            snapshot(id: "candidate", isFavorite: false, area: 90, createdAt: nil)
        ]
        let loader = ControlledReviewAssetSnapshotLoader(snapshots: expectedSnapshots)
        let viewModel = makeViewModel(loader: loader)

        let initialInvocationCount = await loader.invocationCount
        XCTAssertEqual(initialInvocationCount, 0)
        XCTAssertFalse(viewModel.hasLoadedReviewState)
        XCTAssertEqual(viewModel.assetCount, 0)

        let loadTask = Task { await viewModel.load() }
        await loader.waitUntilStarted()

        XCTAssertFalse(viewModel.hasLoadedReviewState)
        XCTAssertEqual(viewModel.assetCount, 0)

        await loader.finish()
        await loadTask.value

        XCTAssertTrue(viewModel.hasLoadedReviewState)
        XCTAssertEqual(viewModel.assetCount, 2)
        XCTAssertEqual(viewModel.bestShotAssetID, "best")
        XCTAssertEqual(viewModel.displayedAssetIdentifiers, ["best", "candidate"])
    }

    func testCancelledAssetSnapshotPreparationDoesNotPublishPartialState() async {
        let loader = ControlledReviewAssetSnapshotLoader(
            snapshots: [snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil)]
        )
        let viewModel = makeViewModel(loader: loader)
        let loadTask = Task { await viewModel.load() }
        await loader.waitUntilStarted()

        loadTask.cancel()
        await loadTask.value

        XCTAssertFalse(viewModel.hasLoadedReviewState)
        XCTAssertEqual(viewModel.assetCount, 0)
        XCTAssertTrue(viewModel.bestShotAssetID.isEmpty)
    }

    func testLoadRestoresPersistedSelection() async throws {
        let state = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: ["candidate"],
            mode: .selection,
            status: .inReview,
            estimatedSavingsBytes: 1_024
        )
        await repository.setStoredStates([clusterID: state])
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: false, area: 900, createdAt: nil),
                snapshot(id: "candidate", isFavorite: false, area: 500, createdAt: nil)
            ]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "best")
        XCTAssertEqual(viewModel.selectedAssetIDs, ["candidate"])
        // Nothing but the best shot is kept, but the review was never finished,
        // so the cluster stays open instead of counting itself as reviewed.
        XCTAssertEqual(viewModel.reviewStatus, .inReview)
        XCTAssertFalse(viewModel.isBestShotCelebrationVisible)
        XCTAssertNil(viewModel.bestShotCelebrationCue)
    }

    func testSelectAllExceptBestExcludesBestShot() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.selectAllExceptBest()

        XCTAssertEqual(viewModel.selectedAssetIDs, ["one", "two"])
        XCTAssertEqual(viewModel.reviewStatus, .inReview)
        XCTAssertFalse(viewModel.isBestShotCelebrationVisible)
        XCTAssertEqual(
            viewModel.currentAlikeReaction?.state,
            .cleanupReady(AlikeCleanupSummary(itemCount: 2, estimatedSavingsBytes: 85))
        )
    }

    func testConfirmingReviewCompletesClusterAndCelebrates() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.selectAllExceptBest()
        viewModel.toggleReviewConfirmation()

        XCTAssertTrue(viewModel.isReviewConfirmed)
        XCTAssertEqual(viewModel.reviewStatus, .reviewed)
        XCTAssertTrue(viewModel.isBestShotCelebrationVisible)
        XCTAssertEqual(viewModel.bestShotCelebrationCue?.id.generation, 1)
    }

    func testConfirmingReviewWithSeveralKeptPhotosStillCompletesCluster() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "two")
        viewModel.toggleReviewConfirmation()

        XCTAssertEqual(viewModel.selectedAssetIDs, ["two"])
        XCTAssertEqual(viewModel.keptCount, 2)
        XCTAssertEqual(viewModel.reviewStatus, .reviewed)
    }

    func testConfirmingReviewWithoutSelectionKeepsEveryPhoto() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.toggleReviewConfirmation()

        XCTAssertTrue(viewModel.selectedAssetIDs.isEmpty)
        XCTAssertEqual(viewModel.reviewStatus, .reviewed)
        XCTAssertEqual(viewModel.estimatedSavingsBytes, 0)
    }

    func testTogglingReviewConfirmationTwiceReopensCluster() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "one")
        viewModel.toggleReviewConfirmation()
        viewModel.toggleReviewConfirmation()

        XCTAssertFalse(viewModel.isReviewConfirmed)
        XCTAssertEqual(viewModel.reviewStatus, .inReview)
    }

    func testEditingSelectionAfterConfirmationReopensCluster() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.toggleReviewConfirmation()
        viewModel.toggleSelection(for: "one")

        XCTAssertFalse(viewModel.isReviewConfirmed)
        XCTAssertEqual(viewModel.reviewStatus, .inReview)
    }

    func testConfirmedReviewSurvivesReload() async throws {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "two")
        viewModel.toggleReviewConfirmation()
        await viewModel.save()

        let stored = try await repository.loadReviewState(clusterID: clusterID)
        XCTAssertEqual(stored?.isReviewConfirmed, true)
        XCTAssertEqual(stored?.status, .reviewed)

        let reloaded = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )
        await reloaded.load()

        XCTAssertTrue(reloaded.isReviewConfirmed)
        XCTAssertEqual(reloaded.selectedAssetIDs, ["two"])
        XCTAssertEqual(reloaded.reviewStatus, .reviewed)
    }

    func testSetBestShotPromotesPhotoAndDeselectsIt() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "one")
        viewModel.setBestShot("one")

        XCTAssertEqual(viewModel.bestShotAssetID, "one")
        XCTAssertTrue(viewModel.isBestShotUserSelected)
        XCTAssertTrue(viewModel.selectedAssetIDs.isEmpty)
        XCTAssertEqual(viewModel.reviewStatus, .notReviewed)
    }

    func testSetBestShotOnReviewedClusterSwapsPreviousBestIntoSelection() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.selectAllExceptBest()
        viewModel.toggleReviewConfirmation()
        viewModel.setBestShot("one")

        XCTAssertEqual(viewModel.bestShotAssetID, "one")
        XCTAssertEqual(viewModel.selectedAssetIDs, ["best", "two"])
        XCTAssertEqual(viewModel.reviewStatus, .reviewed)
    }

    /// Promoting a keeper inside a multi-keep review must not push the previous
    /// keeper into the delete pile: the user kept it on purpose.
    func testSetBestShotOnMultiKeepReviewLeavesPreviousBestKept() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "two")
        viewModel.toggleReviewConfirmation()
        viewModel.setBestShot("one")

        XCTAssertEqual(viewModel.bestShotAssetID, "one")
        XCTAssertEqual(viewModel.selectedAssetIDs, ["two"])
        XCTAssertEqual(viewModel.reviewStatus, .reviewed)
    }

    func testSetBestShotOnPartiallyReviewedClusterLeavesPreviousBestUnselected() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "two")
        viewModel.setBestShot("one")

        XCTAssertEqual(viewModel.bestShotAssetID, "one")
        XCTAssertEqual(viewModel.selectedAssetIDs, ["two"])
        XCTAssertEqual(viewModel.reviewStatus, .inReview)
    }

    func testSetBestShotIgnoresUnknownAndAlreadyBestIdentifiers() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.setBestShot("missing")
        viewModel.setBestShot("best")

        XCTAssertEqual(viewModel.bestShotAssetID, "best")
        XCTAssertFalse(viewModel.isBestShotUserSelected)
    }

    func testSetBestShotPersistsUserOverride() async throws {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.setBestShot("one")
        await viewModel.save()

        let stored = try await repository.loadReviewState(clusterID: clusterID)
        XCTAssertEqual(stored?.bestShotLocalIdentifier, "one")
        XCTAssertEqual(stored?.isBestShotUserSelected, true)
    }

    func testLoadRestoresUserSelectedBestShot() async {
        let state = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "one",
            isBestShotUserSelected: true,
            selectedLocalIdentifiers: [],
            mode: .selection,
            status: .notReviewed,
            estimatedSavingsBytes: 0
        )
        await repository.setStoredStates([clusterID: state])
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "one")
        XCTAssertTrue(viewModel.isBestShotUserSelected)
    }

    func testLoadDropsUserOverrideWhenChosenPhotoIsGone() async {
        let state = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "removed",
            isBestShotUserSelected: true,
            selectedLocalIdentifiers: [],
            mode: .selection,
            status: .notReviewed,
            estimatedSavingsBytes: 0
        )
        await repository.setStoredStates([clusterID: state])
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "best")
        XCTAssertFalse(viewModel.isBestShotUserSelected)
    }

    func testLoadNormalizesLegacyKeepBestOnlyModeAndKeepsGridVisible() async {
        let state = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: ["one"],
            mode: .keepBestOnly,
            status: .reviewed,
            estimatedSavingsBytes: 45
        )
        await repository.setStoredStates([clusterID: state])
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.selectedAssetIDs, ["one"])
        XCTAssertEqual(viewModel.reviewStatus, .reviewed)
        XCTAssertEqual(viewModel.reviewMode, .selection)
        XCTAssertEqual(viewModel.displayedAssetIdentifiers, ["best", "one"])
    }

    func testClearSelectionResetsState() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.selectAllExceptBest()
        viewModel.clearSelection()

        XCTAssertTrue(viewModel.selectedAssetIDs.isEmpty)
        XCTAssertEqual(viewModel.reviewStatus, .notReviewed)
        XCTAssertEqual(viewModel.estimatedSavingsBytes, 0)
        XCTAssertFalse(viewModel.isBestShotCelebrationVisible)
    }

    func testTogglingBestShotDoesNothing() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "best")

        XCTAssertTrue(viewModel.selectedAssetIDs.isEmpty)
        XCTAssertEqual(viewModel.reviewStatus, .notReviewed)
    }

    func testMissingPersistedBestShotRecomputesFallback() async {
        let state = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "missing",
            selectedLocalIdentifiers: ["candidate"],
            mode: .selection,
            status: .inReview,
            estimatedSavingsBytes: 10
        )
        await repository.setStoredStates([clusterID: state])
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 200, createdAt: nil),
                snapshot(id: "candidate", isFavorite: false, area: 100, createdAt: nil)
            ]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "best")
        XCTAssertEqual(viewModel.selectedAssetIDs, ["candidate"])
    }

    func testLoadPreservesNeedsReReviewStatusForResurfacedCluster() async {
        let state = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: [],
            mode: .selection,
            status: .needsReReview,
            estimatedSavingsBytes: 0,
            resurfacingState: .changed
        )
        await repository.setStoredStates([clusterID: state])
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 200, createdAt: nil),
                snapshot(id: "candidate", isFavorite: false, area: 100, createdAt: nil)
            ]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.reviewStatus, .needsReReview)
        XCTAssertTrue(viewModel.selectedAssetIDs.isEmpty)
        XCTAssertEqual(viewModel.estimatedSavingsBytes, 0)
    }

    func testEstimatedSavingsUsesSelectedAssetsOnly() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 300, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 200, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 100, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "one")

        XCTAssertEqual(viewModel.estimatedSavingsBytes, 100)
        XCTAssertEqual(
            viewModel.maximumEstimatedSavingsText,
            ByteCountFormatter.string(fromByteCount: 150, countStyle: .file)
        )
        XCTAssertEqual(viewModel.reviewStatus, .inReview)
        XCTAssertFalse(viewModel.isBestShotCelebrationVisible)
    }

    func testCleanupReadyReactionTracksSelectionChanges() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )
        await viewModel.load()

        viewModel.toggleSelection(for: "one")
        viewModel.toggleSelection(for: "two")

        XCTAssertEqual(
            viewModel.currentAlikeReaction?.state,
            .cleanupReady(AlikeCleanupSummary(itemCount: 2, estimatedSavingsBytes: 85))
        )
    }

    func testBestShotBreaksTieByIdentifier() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "a", isFavorite: false, area: 100, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "b", isFavorite: false, area: 100, createdAt: Date(timeIntervalSince1970: 10))
            ]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "a")
    }

    func testBestShotPrefersNewerModificationDateWhenOtherSignalsMatch() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(
                    id: "older",
                    isFavorite: false,
                    area: 100,
                    createdAt: Date(timeIntervalSince1970: 10),
                    modifiedAt: Date(timeIntervalSince1970: 20)
                ),
                snapshot(
                    id: "newer",
                    isFavorite: false,
                    area: 100,
                    createdAt: Date(timeIntervalSince1970: 10),
                    modifiedAt: Date(timeIntervalSince1970: 30)
                )
            ]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "newer")
    }

    func testSelectAllExceptBestKeepsAllAssetsVisible() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.selectAllExceptBest()

        XCTAssertEqual(viewModel.displayedAssetIdentifiers, ["best", "one", "two"])
        XCTAssertEqual(viewModel.selectedAssetIDs, ["one", "two"])
    }
}
