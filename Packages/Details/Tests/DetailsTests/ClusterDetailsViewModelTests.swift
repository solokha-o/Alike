import Core
import Foundation
import Photos
import Testing
@testable import Details

@MainActor
struct ClusterDetailsViewModelTests: ClusterDetailsViewModelFixture {
    let repository = MockClusterReviewStateRepository()
    let cleanupService = MockPhotoCleanupService()
    let cleanupHistoryRepository = MockCleanupHistoryRepository()
    let clusterID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

    @Test func testLoadWithoutPersistedStateComputesBestShot() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "a", isFavorite: false, area: 800, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "b", isFavorite: true, area: 200, createdAt: Date(timeIntervalSince1970: 1)),
            ]
        )

        await viewModel.load()

        #expect(viewModel.bestShotAssetID == "b")
        #expect(viewModel.selectedAssetIDs.isEmpty)
        #expect(viewModel.reviewStatus == .notReviewed)
    }

    @Test func testLoadKeepsComparisonVisibleForUnreviewedCluster() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "candidate", isFavorite: false, area: 90, createdAt: nil),
            ]
        )

        #expect(!viewModel.hasLoadedReviewState)
        #expect(!viewModel.isBestShotCelebrationVisible)

        await viewModel.load()

        #expect(viewModel.hasLoadedReviewState)
        #expect(!viewModel.isBestShotCelebrationVisible)
    }

    @Test func testLoadDoesNotShowBestShotCelebrationForSingleAsset() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "only", isFavorite: true, area: 100, createdAt: nil),
            ]
        )

        await viewModel.load()

        #expect(viewModel.hasLoadedReviewState)
        #expect(!viewModel.isBestShotCelebrationVisible)
    }

    @Test func testInitializationDefersAssetSnapshotPreparationUntilLoad() async {
        let expectedSnapshots = [
            snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
            snapshot(id: "candidate", isFavorite: false, area: 90, createdAt: nil),
        ]
        let loader = ControlledReviewAssetSnapshotLoader(snapshots: expectedSnapshots)
        let viewModel = makeViewModel(loader: loader)

        let initialInvocationCount = await loader.invocationCount
        #expect(initialInvocationCount == 0)
        #expect(!viewModel.hasLoadedReviewState)
        #expect(viewModel.assetCount == 0)

        let loadTask = Task { await viewModel.load() }
        await loader.waitUntilStarted()

        #expect(!viewModel.hasLoadedReviewState)
        #expect(viewModel.assetCount == 0)

        await loader.finish()
        await loadTask.value

        #expect(viewModel.hasLoadedReviewState)
        #expect(viewModel.assetCount == 2)
        #expect(viewModel.bestShotAssetID == "best")
        #expect(viewModel.displayedAssetIdentifiers == ["best", "candidate"])
    }

    @Test func testCancelledAssetSnapshotPreparationDoesNotPublishPartialState() async {
        let loader = ControlledReviewAssetSnapshotLoader(
            snapshots: [snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil)]
        )
        let viewModel = makeViewModel(loader: loader)
        let loadTask = Task { await viewModel.load() }
        await loader.waitUntilStarted()

        loadTask.cancel()
        await loadTask.value

        #expect(!viewModel.hasLoadedReviewState)
        #expect(viewModel.assetCount == 0)
        #expect(viewModel.bestShotAssetID.isEmpty)
    }

    @Test func testLoadRestoresPersistedSelection() async {
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
                snapshot(id: "candidate", isFavorite: false, area: 500, createdAt: nil),
            ]
        )

        await viewModel.load()

        #expect(viewModel.bestShotAssetID == "best")
        #expect(viewModel.selectedAssetIDs == ["candidate"])
        // Nothing but the best shot is kept, but the review was never finished,
        // so the cluster stays open instead of counting itself as reviewed.
        #expect(viewModel.reviewStatus == .inReview)
        #expect(!viewModel.isBestShotCelebrationVisible)
        #expect(viewModel.bestShotCelebrationCue == nil)
    }

    @Test func testSelectAllExceptBestExcludesBestShot() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.selectAllExceptBest()

        #expect(viewModel.selectedAssetIDs == ["one", "two"])
        #expect(viewModel.reviewStatus == .inReview)
        #expect(!viewModel.isBestShotCelebrationVisible)
        #expect(viewModel.currentAlikeReaction?.state == .cleanupReady(AlikeCleanupSummary(itemCount: 2, estimatedSavingsBytes: 85)))
    }

    @Test func testConfirmingReviewCompletesClusterAndCelebrates() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.selectAllExceptBest()
        viewModel.toggleReviewConfirmation()

        #expect(viewModel.isReviewConfirmed)
        #expect(viewModel.reviewStatus == .reviewed)
        #expect(viewModel.isBestShotCelebrationVisible)
        #expect(viewModel.bestShotCelebrationCue?.id.generation == 1)
    }

    @Test func testConfirmingReviewWithSeveralKeptPhotosStillCompletesCluster() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "two")
        viewModel.toggleReviewConfirmation()

        #expect(viewModel.selectedAssetIDs == ["two"])
        #expect(viewModel.keptCount == 2)
        #expect(viewModel.reviewStatus == .reviewed)
    }

    @Test func testConfirmingReviewWithoutSelectionKeepsEveryPhoto() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.toggleReviewConfirmation()

        #expect(viewModel.selectedAssetIDs.isEmpty)
        #expect(viewModel.reviewStatus == .reviewed)
        #expect(viewModel.estimatedSavingsBytes == 0)
    }

    @Test func testTogglingReviewConfirmationTwiceReopensCluster() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "one")
        viewModel.toggleReviewConfirmation()
        viewModel.toggleReviewConfirmation()

        #expect(!viewModel.isReviewConfirmed)
        #expect(viewModel.reviewStatus == .inReview)
    }

    @Test func testEditingSelectionAfterConfirmationReopensCluster() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.toggleReviewConfirmation()
        viewModel.toggleSelection(for: "one")

        #expect(!viewModel.isReviewConfirmed)
        #expect(viewModel.reviewStatus == .inReview)
    }

    @Test func testConfirmedReviewSurvivesReload() async throws {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "two")
        viewModel.toggleReviewConfirmation()
        await viewModel.save()

        let stored = try await repository.loadReviewState(clusterID: clusterID)
        #expect(stored?.isReviewConfirmed == true)
        #expect(stored?.status == .reviewed)

        let reloaded = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil),
            ]
        )
        await reloaded.load()

        #expect(reloaded.isReviewConfirmed)
        #expect(reloaded.selectedAssetIDs == ["two"])
        #expect(reloaded.reviewStatus == .reviewed)
    }

    @Test func testSetBestShotPromotesPhotoAndDeselectsIt() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "one")
        viewModel.setBestShot("one")

        #expect(viewModel.bestShotAssetID == "one")
        #expect(viewModel.isBestShotUserSelected)
        #expect(viewModel.selectedAssetIDs.isEmpty)
        #expect(viewModel.reviewStatus == .notReviewed)
    }

    @Test func testSetBestShotOnReviewedClusterSwapsPreviousBestIntoSelection() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.selectAllExceptBest()
        viewModel.toggleReviewConfirmation()
        viewModel.setBestShot("one")

        #expect(viewModel.bestShotAssetID == "one")
        #expect(viewModel.selectedAssetIDs == ["best", "two"])
        #expect(viewModel.reviewStatus == .reviewed)
    }

    /// Promoting a keeper inside a multi-keep review must not push the previous
    /// keeper into the delete pile: the user kept it on purpose.
    @Test func testSetBestShotOnMultiKeepReviewLeavesPreviousBestKept() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "two")
        viewModel.toggleReviewConfirmation()
        viewModel.setBestShot("one")

        #expect(viewModel.bestShotAssetID == "one")
        #expect(viewModel.selectedAssetIDs == ["two"])
        #expect(viewModel.reviewStatus == .reviewed)
    }

    @Test func testSetBestShotOnPartiallyReviewedClusterLeavesPreviousBestUnselected() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "two")
        viewModel.setBestShot("one")

        #expect(viewModel.bestShotAssetID == "one")
        #expect(viewModel.selectedAssetIDs == ["two"])
        #expect(viewModel.reviewStatus == .inReview)
    }

    @Test func testSetBestShotIgnoresUnknownAndAlreadyBestIdentifiers() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.setBestShot("missing")
        viewModel.setBestShot("best")

        #expect(viewModel.bestShotAssetID == "best")
        #expect(!viewModel.isBestShotUserSelected)
    }

    @Test func testSetBestShotPersistsUserOverride() async throws {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.setBestShot("one")
        await viewModel.save()

        let stored = try await repository.loadReviewState(clusterID: clusterID)
        #expect(stored?.bestShotLocalIdentifier == "one")
        #expect(stored?.isBestShotUserSelected == true)
    }

    @Test func testLoadRestoresUserSelectedBestShot() async {
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
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
            ]
        )

        await viewModel.load()

        #expect(viewModel.bestShotAssetID == "one")
        #expect(viewModel.isBestShotUserSelected)
    }

    @Test func testLoadDropsUserOverrideWhenChosenPhotoIsGone() async {
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
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
            ]
        )

        await viewModel.load()

        #expect(viewModel.bestShotAssetID == "best")
        #expect(!viewModel.isBestShotUserSelected)
    }

    @Test func testLoadNormalizesLegacyKeepBestOnlyModeAndKeepsGridVisible() async {
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
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
            ]
        )

        await viewModel.load()

        #expect(viewModel.selectedAssetIDs == ["one"])
        #expect(viewModel.reviewStatus == .reviewed)
        #expect(viewModel.reviewMode == .selection)
        #expect(viewModel.displayedAssetIdentifiers == ["best", "one"])
    }

    @Test func testClearSelectionResetsState() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.selectAllExceptBest()
        viewModel.clearSelection()

        #expect(viewModel.selectedAssetIDs.isEmpty)
        #expect(viewModel.reviewStatus == .notReviewed)
        #expect(viewModel.estimatedSavingsBytes == 0)
        #expect(!viewModel.isBestShotCelebrationVisible)
    }

    @Test func testTogglingBestShotDoesNothing() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "best")

        #expect(viewModel.selectedAssetIDs.isEmpty)
        #expect(viewModel.reviewStatus == .notReviewed)
    }

    @Test func testMissingPersistedBestShotRecomputesFallback() async {
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
                snapshot(id: "candidate", isFavorite: false, area: 100, createdAt: nil),
            ]
        )

        await viewModel.load()

        #expect(viewModel.bestShotAssetID == "best")
        #expect(viewModel.selectedAssetIDs == ["candidate"])
    }

    @Test func testLoadPreservesNeedsReReviewStatusForResurfacedCluster() async {
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
                snapshot(id: "candidate", isFavorite: false, area: 100, createdAt: nil),
            ]
        )

        await viewModel.load()

        #expect(viewModel.reviewStatus == .needsReReview)
        #expect(viewModel.selectedAssetIDs.isEmpty)
        #expect(viewModel.estimatedSavingsBytes == 0)
    }

    @Test func testEstimatedSavingsUsesSelectedAssetsOnly() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 300, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 200, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 100, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "one")

        #expect(viewModel.estimatedSavingsBytes == 100)
        #expect(viewModel.maximumEstimatedSavingsText == ByteCountFormatter.string(fromByteCount: 150, countStyle: .file))
        #expect(viewModel.reviewStatus == .inReview)
        #expect(!viewModel.isBestShotCelebrationVisible)
    }

    @Test func testCleanupReadyReactionTracksSelectionChanges() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil),
            ]
        )
        await viewModel.load()

        viewModel.toggleSelection(for: "one")
        viewModel.toggleSelection(for: "two")

        #expect(viewModel.currentAlikeReaction?.state == .cleanupReady(AlikeCleanupSummary(itemCount: 2, estimatedSavingsBytes: 85)))
    }

    @Test func testBestShotBreaksTieByIdentifier() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "a", isFavorite: false, area: 100, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "b", isFavorite: false, area: 100, createdAt: Date(timeIntervalSince1970: 10)),
            ]
        )

        await viewModel.load()

        #expect(viewModel.bestShotAssetID == "a")
    }

    @Test func testBestShotPrefersNewerModificationDateWhenOtherSignalsMatch() async {
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
                ),
            ]
        )

        await viewModel.load()

        #expect(viewModel.bestShotAssetID == "newer")
    }

    @Test func testSelectAllExceptBestKeepsAllAssetsVisible() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil),
            ]
        )

        await viewModel.load()
        viewModel.selectAllExceptBest()

        #expect(viewModel.displayedAssetIdentifiers == ["best", "one", "two"])
        #expect(viewModel.selectedAssetIDs == ["one", "two"])
    }
}
