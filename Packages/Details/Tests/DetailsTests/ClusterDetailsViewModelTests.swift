import XCTest
import Core
import Photos
@testable import Details

@MainActor
final class ClusterDetailsViewModelTests: XCTestCase {
    private var repository: MockClusterReviewStateRepository!
    private var cleanupService: MockPhotoCleanupService!
    private var cleanupHistoryRepository: MockCleanupHistoryRepository!
    private let clusterID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

    override func setUp() async throws {
        repository = MockClusterReviewStateRepository()
        cleanupService = MockPhotoCleanupService()
        cleanupHistoryRepository = MockCleanupHistoryRepository()
    }

    override func tearDown() async throws {
        repository = nil
        cleanupService = nil
        cleanupHistoryRepository = nil
    }

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

    func testConfirmDeleteCallsCleanupServiceAndPersistsHistory() async throws {
        let completionRecord = CleanupCompletionRecord(
            sourceClusterID: clusterID,
            deletedCount: 2,
            estimatedSavingsBytes: 300
        )
        await cleanupService.setDeleteAssetsResult(.success(completionRecord))
        let existingState = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: ["one", "two"],
            mode: .selection,
            status: .reviewed,
            estimatedSavingsBytes: 300
        )
        await repository.setStoredStates([clusterID: existingState])

        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 120, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 100, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 90, createdAt: nil)
            ],
            premiumAccess: MockPremiumAccessController(unlockedFeatures: [.batchCleanup])
        )

        await viewModel.load()
        viewModel.selectAllExceptBest()
        viewModel.requestDeleteConfirmation()
        await viewModel.confirmDelete()

        let cleanupDidRun = await cleanupService.didCallDeleteAssets
        let lastSelection = await cleanupService.lastLocalIdentifiers
        let storedEntries = await cleanupHistoryRepository.entries
        let remainingState = try await repository.loadReviewState(clusterID: clusterID)

        XCTAssertTrue(cleanupDidRun)
        XCTAssertEqual(lastSelection, Set(["one", "two"]))
        XCTAssertEqual(storedEntries, [completionRecord])
        XCTAssertNil(remainingState)
        XCTAssertEqual(viewModel.pendingCompletionRecord, completionRecord)
        XCTAssertTrue(viewModel.hasCompletedCleanup)
        XCTAssertFalse(viewModel.isDeleting)
    }

    /// The keeper's protection is a selection invariant, so assert it where it
    /// actually matters: the identifiers handed to the cleanup service.
    func testConfirmDeleteNeverSendsTheBestShotToCleanup() async {
        await cleanupService.setDeleteAssetsResult(.success(
            CleanupCompletionRecord(
                sourceClusterID: clusterID,
                deletedCount: 1,
                estimatedSavingsBytes: 100
            )
        ))
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 120, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 100, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 90, createdAt: nil)
            ],
            premiumAccess: MockPremiumAccessController(unlockedFeatures: [.batchCleanup])
        )

        await viewModel.load()
        viewModel.selectAllExceptBest()
        viewModel.setBestShot("one")
        viewModel.toggleSelection(for: "best")
        viewModel.toggleSelection(for: "two")
        await viewModel.confirmDelete()

        let lastSelection = await cleanupService.lastLocalIdentifiers
        XCTAssertEqual(viewModel.bestShotAssetID, "one")
        XCTAssertFalse(lastSelection?.contains("one") ?? true)
        XCTAssertEqual(lastSelection, Set(["best"]))
    }

    func testConfirmDeletePublishesCompletionAfterReviewStateRemovalFinishes() async {
        let completionRecord = CleanupCompletionRecord(
            sourceClusterID: clusterID,
            deletedCount: 1,
            estimatedSavingsBytes: 100
        )
        let reviewState = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: ["candidate"],
            mode: .selection,
            status: .reviewed,
            estimatedSavingsBytes: 100
        )
        let suspendedRepository = SuspendedClusterReviewStateRepository(state: reviewState)
        await cleanupService.setDeleteAssetsResult(.success(completionRecord))
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "candidate", isFavorite: false, area: 90, createdAt: nil)
            ],
            reviewRepository: suspendedRepository
        )
        await viewModel.load()
        viewModel.selectAllExceptBest()

        let deleteTask = Task { await viewModel.confirmDelete() }
        await suspendedRepository.waitUntilDeleteStarts()

        XCTAssertNil(viewModel.pendingCompletionRecord)
        XCTAssertTrue(viewModel.isDeleting)
        let storedEntries = await cleanupHistoryRepository.entries
        XCTAssertEqual(storedEntries, [completionRecord])

        await suspendedRepository.finishDelete()
        await deleteTask.value

        XCTAssertEqual(viewModel.pendingCompletionRecord, completionRecord)
        XCTAssertFalse(viewModel.isDeleting)
    }

    func testConfirmDeleteWaitsForCompletionDelayBeforePublishing() async throws {
        let completionRecord = CleanupCompletionRecord(
            sourceClusterID: clusterID,
            deletedCount: 1,
            estimatedSavingsBytes: 100
        )
        let completionDelay = SuspendedClusterCleanupCompletionDelay()
        await cleanupService.setDeleteAssetsResult(.success(completionRecord))
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "candidate", isFavorite: false, area: 90, createdAt: nil)
            ],
            completionDelay: { await completionDelay.wait() }
        )
        await viewModel.load()
        viewModel.selectAllExceptBest()

        let deleteTask = Task { await viewModel.confirmDelete() }
        await completionDelay.waitUntilStarted()

        let remainingState = try await repository.loadReviewState(clusterID: clusterID)
        XCTAssertNil(remainingState)
        XCTAssertNil(viewModel.pendingCompletionRecord)
        XCTAssertTrue(viewModel.isDeleting)

        await completionDelay.finish()
        await deleteTask.value

        XCTAssertEqual(viewModel.pendingCompletionRecord, completionRecord)
        XCTAssertFalse(viewModel.isDeleting)
    }

    func testConfirmDeleteFailurePreservesSelectionAndShowsMessage() async {
        await cleanupService.setDeleteAssetsResult(.failure(PhotoCleanupError.deleteFailed))
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.selectAllExceptBest()
        await viewModel.confirmDelete()

        XCTAssertEqual(viewModel.selectedAssetIDs, ["one"])
        XCTAssertNil(viewModel.pendingCompletionRecord)
        XCTAssertEqual(viewModel.actionErrorMessage, DetailsL10n.Common.couldntMoveSelectedPhotosPlease)
        XCTAssertEqual(
            viewModel.currentAlikeReaction?.state,
            .recoverableError(AlikeErrorContext(operation: .cleanup))
        )
        XCTAssertFalse(viewModel.isDeleting)

        viewModel.clearActionError()

        XCTAssertEqual(
            viewModel.currentAlikeReaction?.state,
            .cleanupReady(AlikeCleanupSummary(itemCount: 1, estimatedSavingsBytes: 45))
        )
    }

    func testConfirmDeleteDoesNotRunWithoutSelection() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()
        await viewModel.confirmDelete()

        let cleanupDidRun = await cleanupService.didCallDeleteAssets
        XCTAssertFalse(cleanupDidRun)
        XCTAssertEqual(viewModel.actionErrorMessage, DetailsL10n.Common.selectAtLeastOnePhoto)
    }

    func testDismissingDeleteErrorClearsErrorState() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "candidate", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()
        await viewModel.confirmDelete()

        XCTAssertTrue(viewModel.isActionErrorPresented)

        viewModel.isActionErrorPresented = false

        XCTAssertFalse(viewModel.isActionErrorPresented)
        XCTAssertNil(viewModel.actionErrorMessage)
        XCTAssertFalse(viewModel.shouldOfferOpenSettings)
    }

    func testDeleteConfirmationCopyReflectsSelectionCountAndSavings() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 300, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 200, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 100, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "one")

        XCTAssertEqual(
            viewModel.deleteConfirmationTitle,
            DetailsL10n.ClusterDetails.deleteAlertTitle(1)
        )
        XCTAssertEqual(
            viewModel.deleteConfirmationMessage,
            String(
                format: DetailsL10n.ClusterDetails.selectedPhotoWillBeRemoved,
                viewModel.estimatedSavingsText
            )
        )

        viewModel.toggleSelection(for: "two")

        XCTAssertEqual(
            viewModel.deleteConfirmationTitle,
            DetailsL10n.ClusterDetails.deleteAlertTitle(2)
        )
        XCTAssertEqual(
            viewModel.deleteConfirmationMessage,
            String(
                format: DetailsL10n.ClusterDetails.selectedPhotosWillBeRemoved,
                viewModel.estimatedSavingsText
            )
        )
    }

    func testFreeUserCanRequestSinglePhotoCleanup() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )
        await viewModel.load()
        viewModel.selectAllExceptBest()

        let decision = viewModel.requestDeleteConfirmation()

        XCTAssertEqual(decision, .allowed)
        XCTAssertTrue(viewModel.isDeleteConfirmationPresented)
    }

    func testFreeUserCannotRequestOrConfirmMultiPhotoCleanup() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )
        await viewModel.load()
        viewModel.selectAllExceptBest()

        let decision = viewModel.requestDeleteConfirmation()
        await viewModel.confirmDelete()
        let cleanupDidRun = await cleanupService.didCallDeleteAssets

        XCTAssertEqual(decision, .requiresPremium)
        XCTAssertFalse(viewModel.isDeleteConfirmationPresented)
        XCTAssertEqual(viewModel.selectedAssetIDs, ["one", "two"])
        XCTAssertFalse(cleanupDidRun)
    }

    func testContinueFreeKeepsFirstSelectedAssetInVisibleOrder() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )
        await viewModel.load()
        viewModel.selectAllExceptBest()

        XCTAssertTrue(viewModel.requiresPremiumForCurrentSelection)
        await viewModel.continueWithSingleFreeSelection()

        XCTAssertEqual(viewModel.selectedAssetIDs, ["one"])
        XCTAssertFalse(viewModel.requiresPremiumForCurrentSelection)
        XCTAssertTrue(viewModel.isDeleteConfirmationPresented)
    }

    func testPersistedRevisionAdvancesOnlyAfterEachSaveLands() async {
        let reviewRepository = SuspendableSaveClusterReviewStateRepository()
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ],
            reviewRepository: reviewRepository
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.persistedRevision, 0)

        await reviewRepository.suspendNextSave()
        viewModel.toggleSelection(for: "one")
        await reviewRepository.waitUntilSuspendedSaveStarts()

        XCTAssertEqual(viewModel.persistedRevision, 0)

        await reviewRepository.finishSuspendedSave()
        await waitForPersistedRevision(1, on: viewModel)

        viewModel.toggleSelection(for: "one")
        await waitForPersistedRevision(2, on: viewModel)
    }

    func testAwaitPendingPersistenceDoesNotReturnUntilTheInFlightSaveLands() async {
        let reviewRepository = SuspendableSaveClusterReviewStateRepository()
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ],
            reviewRepository: reviewRepository
        )
        await viewModel.load()

        await reviewRepository.suspendNextSave()
        viewModel.toggleSelection(for: "one")
        await reviewRepository.waitUntilSuspendedSaveStarts()
        XCTAssertEqual(viewModel.persistedRevision, 0)

        let waiter = Task { await viewModel.awaitPendingPersistence() }
        await reviewRepository.finishSuspendedSave()
        await waiter.value

        // The host reads the repository as soon as this returns, so the write
        // has to be on disk by now, not merely enqueued.
        XCTAssertEqual(viewModel.persistedRevision, 1)
        let persisted = try? await reviewRepository.loadReviewState(clusterID: clusterID)
        XCTAssertEqual(persisted?.selectedLocalIdentifiers, ["one"])
    }

    func testContinueFreeSerializesEarlierSaveBeforeConfirmationAndDeletion() async {
        let reviewRepository = SuspendableSaveClusterReviewStateRepository()
        await cleanupService.setDeleteAssetsResult(.success(
            CleanupCompletionRecord(
                sourceClusterID: clusterID,
                deletedCount: 1,
                estimatedSavingsBytes: 90
            )
        ))
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ],
            reviewRepository: reviewRepository
        )
        await viewModel.load()
        await reviewRepository.suspendNextSave()
        viewModel.selectAllExceptBest()
        await reviewRepository.waitUntilSuspendedSaveStarts()

        let continueTask = Task {
            await viewModel.continueWithSingleFreeSelection()
        }

        XCTAssertFalse(viewModel.isDeleteConfirmationPresented)

        await reviewRepository.finishSuspendedSave()
        await continueTask.value

        XCTAssertTrue(viewModel.isDeleteConfirmationPresented)
        let persistedFallbackState = await reviewRepository.storedState(clusterID: clusterID)
        XCTAssertEqual(persistedFallbackState?.selectedLocalIdentifiers, ["one"])

        await viewModel.confirmDelete()

        let stateAfterDelete = await reviewRepository.storedState(clusterID: clusterID)
        XCTAssertNil(stateAfterDelete)
    }

    // MARK: - Best Shot quality scoring

    func testScoredBestShotBeatsTheMetadataChoice() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "blurred-favorite", isFavorite: true, area: 4_000, createdAt: Date(timeIntervalSince1970: 20)),
                snapshot(id: "sharp", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10))
            ],
            qualityScores: [("blurred-favorite", 12), ("sharp", 60)]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "sharp")
        XCTAssertEqual(viewModel.bestShotConfidence, .automatic)
        XCTAssertTrue(viewModel.bestShotReasonCodes.contains(.sharper))
    }

    func testPersistedManualOverrideSurvivesARescanWithDifferentScores() async {
        await repository.setStoredStates([clusterID: ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "chosen",
            isBestShotUserSelected: true,
            selectedLocalIdentifiers: [],
            status: .inReview,
            estimatedSavingsBytes: 0
        )])
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "chosen", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "sharper", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            qualityScores: [("chosen", 12), ("sharper", 70)]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "chosen")
        XCTAssertTrue(viewModel.isBestShotUserSelected)
        XCTAssertEqual(viewModel.bestShotConfidence, .automatic)
        XCTAssertTrue(viewModel.bestShotReasonCodes.isEmpty)
    }

    func testUnconfirmedAutomaticBestShotIsReplacedByTheFreshRanking() async {
        await repository.setStoredStates([clusterID: ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "old-pick",
            isBestShotUserSelected: false,
            selectedLocalIdentifiers: [],
            status: .notReviewed,
            estimatedSavingsBytes: 0
        )])
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "old-pick", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "sharper", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            qualityScores: [("old-pick", 12), ("sharper", 70)]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "sharper")
        XCTAssertFalse(viewModel.isBestShotUserSelected)
    }

    func testFinishedReviewKeepsItsBestShotEvenWhenScoresDisagree() async {
        await repository.setStoredStates([clusterID: ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "reviewed-pick",
            isBestShotUserSelected: false,
            selectedLocalIdentifiers: ["sharper"],
            isReviewConfirmed: true,
            status: .reviewed,
            estimatedSavingsBytes: 0
        )])
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "reviewed-pick", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "sharper", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            qualityScores: [("reviewed-pick", 12), ("sharper", 70)]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "reviewed-pick")
        XCTAssertEqual(viewModel.reviewStatus, .reviewed)
    }

    func testUnresolvedClusterShowsNoBestShotButKeepsReviewAvailable() async {
        let viewModel = makeViewModel(
            snapshots: weakClusterSnapshots,
            qualityScores: [("a", 4), ("b", 3.6), ("c", 3.8)]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotConfidence, .unresolved)
        XCTAssertTrue(viewModel.bestShotAssetID.isEmpty)
        XCTAssertTrue(viewModel.bestShotReasonCodes.isEmpty)
        XCTAssertTrue(viewModel.isActionBarVisible)

        viewModel.toggleReviewConfirmation()

        XCTAssertTrue(viewModel.isReviewConfirmed)
        XCTAssertEqual(viewModel.reviewStatus, .reviewed)
    }

    func testChoosingABestShotInAnUnresolvedClusterMakesItCertain() async {
        let viewModel = makeViewModel(
            snapshots: weakClusterSnapshots,
            qualityScores: [("a", 4), ("b", 3.6), ("c", 3.8)]
        )
        await viewModel.load()

        viewModel.setBestShot("b")

        XCTAssertEqual(viewModel.bestShotAssetID, "b")
        XCTAssertTrue(viewModel.isBestShotUserSelected)
        XCTAssertEqual(viewModel.bestShotConfidence, .automatic)
    }

    func testMissingQualityScoresKeepTheMetadataBestShot() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "favorite")
        XCTAssertEqual(viewModel.bestShotConfidence, .automatic)
    }

    // MARK: - Anonymous override metrics

    func testOpeningAClusterWithARecommendationCountsIt() async {
        let metrics = MockBestShotOverrideMetricsRepository()
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "sharp", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "blurred", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            qualityScores: [("sharp", 60), ("blurred", 20)],
            overrideMetrics: metrics
        )

        await viewModel.load()

        let recorded = await metrics.recordedRecommendations
        XCTAssertEqual(recorded, [.automatic])
    }

    func testReplacingTheRecommendationIsCountedAsAnOverride() async {
        let metrics = MockBestShotOverrideMetricsRepository()
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "sharp", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "blurred", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            qualityScores: [("sharp", 60), ("blurred", 20)],
            overrideMetrics: metrics
        )
        await viewModel.load()

        viewModel.setBestShot("blurred")
        await waitForRecordedManualPicks(1, on: metrics)

        let picks = await metrics.recordedManualPicks
        XCTAssertEqual(picks, [.automatic])
        let stored = await metrics.metrics
        XCTAssertEqual(stored.manualOverrideCount, 1)
    }

    /// Switching between the user's own picks says nothing about the ranking.
    func testSwitchingBetweenOwnPicksIsNotCountedTwice() async {
        let metrics = MockBestShotOverrideMetricsRepository()
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "a", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "b", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20)),
                snapshot(id: "c", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 30))
            ],
            qualityScores: [("a", 60), ("b", 20), ("c", 25)],
            overrideMetrics: metrics
        )
        await viewModel.load()

        viewModel.setBestShot("b")
        await waitForRecordedManualPicks(1, on: metrics)
        viewModel.setBestShot("c")
        await Task.yield()

        let picks = await metrics.recordedManualPicks
        XCTAssertEqual(picks, [.automatic])
    }

    func testAnUnresolvedClusterRecordsNeitherRecommendationNorOverride() async {
        let metrics = MockBestShotOverrideMetricsRepository()
        let viewModel = makeViewModel(
            snapshots: weakClusterSnapshots,
            qualityScores: [("a", 4), ("b", 3.6), ("c", 3.8)],
            overrideMetrics: metrics
        )
        await viewModel.load()

        viewModel.setBestShot("b")
        await waitForRecordedManualPicks(1, on: metrics)

        let recommendations = await metrics.recordedRecommendations
        let picks = await metrics.recordedManualPicks
        let stored = await metrics.metrics
        XCTAssertTrue(recommendations.isEmpty)
        XCTAssertEqual(picks, [.unresolved])
        XCTAssertEqual(stored.manualOverrideCount, 0)
        XCTAssertEqual(stored.unresolvedManualPickCount, 1)
    }

    /// The screen shows a Best Shot before scoring finishes, so an override can
    /// arrive first. Both sides of the rate have to survive that.
    func testAnOverrideBeforeScoringFinishesStillCountsBothSides() async {
        let metrics = MockBestShotOverrideMetricsRepository()
        let analyzer = StallingPhotoQualityAnalyzer()
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: analyzer,
            overrideMetrics: metrics,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }

        viewModel.setBestShot("plain")
        await waitForRecordedManualPicks(1, on: metrics)
        await analyzer.finish(with: [])
        await loading.value

        let stored = await metrics.metrics
        XCTAssertEqual(stored.recommendationCount, 1)
        XCTAssertEqual(stored.manualOverrideCount, 1)
        XCTAssertEqual(stored.overrideRate, 1, accuracy: 0.000_1)
    }

    private func waitForRecordedManualPicks(
        _ expected: Int,
        on metrics: MockBestShotOverrideMetricsRepository,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            let picks = await metrics.recordedManualPicks
            if picks.count >= expected { return }
            await Task.yield()
        }
        let picks = await metrics.recordedManualPicks
        XCTAssertEqual(picks.count, expected, file: file, line: line)
    }

    private func waitForRecordedExamples(
        _ expected: Int,
        on personalizationRepository: MockBestShotPersonalizationRepository,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            let recorded = await personalizationRepository.recordedExamples
            if recorded.count >= expected { return }
            await Task.yield()
        }
        let recorded = await personalizationRepository.recordedExamples
        XCTAssertEqual(recorded.count, expected, file: file, line: line)
    }

    // MARK: - Personalisation

    func testReplacingTheRecommendationRecordsAnOverrideExample() async {
        let personalizationRepository = MockBestShotPersonalizationRepository()
        let provider = BestShotPersonalizedScoringConfigProvider(repository: personalizationRepository)
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "sharper", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "softer", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            // Close enough that neither candidate is excluded for critical
            // blur (the ranker would then refuse to build an example from
            // it), but still far enough apart to rank cleanly.
            qualityScores: [("sharper", 60), ("softer", 50)],
            personalizedConfigProvider: provider
        )
        await viewModel.load()
        XCTAssertEqual(viewModel.bestShotAssetID, "sharper")

        viewModel.setBestShot("softer")
        await waitForRecordedExamples(1, on: personalizationRepository)

        let recorded = await personalizationRepository.recordedExamples
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.clusterHasFaces, false)
    }

    /// Switching between the user's own picks says nothing about the ranking,
    /// same as the metrics tally above.
    func testSwitchingBetweenOwnPicksRecordsNoOverrideExample() async {
        let personalizationRepository = MockBestShotPersonalizationRepository()
        let provider = BestShotPersonalizedScoringConfigProvider(repository: personalizationRepository)
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "a", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "b", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20)),
                snapshot(id: "c", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 30))
            ],
            qualityScores: [("a", 60), ("b", 20), ("c", 25)],
            personalizedConfigProvider: provider
        )
        await viewModel.load()

        viewModel.setBestShot("b")
        await waitForRecordedExamples(1, on: personalizationRepository)
        viewModel.setBestShot("c")
        await Task.yield()
        await Task.yield()

        let recorded = await personalizationRepository.recordedExamples
        XCTAssertEqual(recorded.count, 1)
    }

    func testNoOverrideExampleWhenScoresNeverLoaded() async {
        let personalizationRepository = MockBestShotPersonalizationRepository()
        let provider = BestShotPersonalizedScoringConfigProvider(repository: personalizationRepository)
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "a", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "b", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            personalizedConfigProvider: provider
        )
        await viewModel.load()

        viewModel.setBestShot("a")
        await Task.yield()
        await Task.yield()

        let recorded = await personalizationRepository.recordedExamples
        XCTAssertTrue(recorded.isEmpty)
    }

    /// Proves the wiring is live: the same two candidates rank differently
    /// once the provider's config is seeded with weights that favor a
    /// different component than the global config does.
    func testPersonalizedConfigProviderConfigDrivesTheRanking() async {
        let signals: [String: PhotoQualitySignals] = [
            "sharpButClipped": PhotoQualitySignals(
                globalSharpness: 120,
                darkClippedFraction: 0.10,
                subjectLumaStdDev: 0.25,
                noiseEstimate: 0.1,
                pixelArea: 1_000
            ),
            "softButExposed": PhotoQualitySignals(
                globalSharpness: 100,
                subjectLumaStdDev: 0.25,
                noiseEstimate: 0.1,
                pixelArea: 1_000
            )
        ]
        let snapshots = [
            snapshot(id: "sharpButClipped", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
            snapshot(id: "softButExposed", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
        ]

        let globalViewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: StubSignalsPhotoQualityAnalyzer(signalsByIdentifier: signals),
            assetSnapshots: snapshots,
            completionDelay: {}
        )
        await globalViewModel.load()
        XCTAssertEqual(globalViewModel.bestShotAssetID, "sharpButClipped")

        let personalizationRepository = MockBestShotPersonalizationRepository()
        let seededWeights = BestShotPersonalWeights(
            withFaces: PhotoQualityScoringConfig.current.weightsWithFaces,
            withoutFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.05,
                faceQuality: 0,
                exposure: 0.75,
                noiseArtifacts: 0.15,
                resolution: 0.05
            ),
            scoringModelVersion: PhotoQualityScoringConfig.current.scoringModelVersion,
            withFacesExampleCount: 0,
            withoutFacesExampleCount: 20
        )
        await personalizationRepository.setWeights(seededWeights)
        let provider = BestShotPersonalizedScoringConfigProvider(repository: personalizationRepository)

        let personalizedViewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: StubSignalsPhotoQualityAnalyzer(signalsByIdentifier: signals),
            personalizedConfigProvider: provider,
            assetSnapshots: snapshots,
            completionDelay: {}
        )
        await personalizedViewModel.load()
        XCTAssertEqual(personalizedViewModel.bestShotAssetID, "softButExposed")
    }

    func testAnUnresolvedClusterCannotBeEmptied() async {
        let viewModel = makeViewModel(
            snapshots: weakClusterSnapshots,
            qualityScores: [("a", 4), ("b", 3.6), ("c", 3.8)]
        )
        await viewModel.load()
        XCTAssertTrue(viewModel.bestShotAssetID.isEmpty)

        for identifier in ["a", "b", "c"] {
            viewModel.toggleSelection(for: identifier)
        }

        // Nothing is protected while no Best Shot exists, so nothing may be
        // selected for deletion either.
        XCTAssertTrue(viewModel.selectedAssetIDs.isEmpty)
        XCTAssertFalse(viewModel.isDeleteActionVisible)

        viewModel.setBestShot("b")
        viewModel.toggleSelection(for: "a")

        XCTAssertEqual(viewModel.selectedAssetIDs, ["a"])
    }

    func testAStoredSelectionIsDroppedWhileNoBestShotExists() async {
        await repository.setStoredStates([clusterID: ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "",
            isBestShotUserSelected: false,
            selectedLocalIdentifiers: ["a", "b", "c"],
            status: .inReview,
            estimatedSavingsBytes: 0
        )])
        let viewModel = makeViewModel(
            snapshots: weakClusterSnapshots,
            qualityScores: [("a", 4), ("b", 3.6), ("c", 3.8)]
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.selectedAssetIDs.isEmpty)
        XCTAssertFalse(viewModel.isDeleteActionVisible)
    }

    /// A cluster the user already finished keeps its Best Shot, so the badge and
    /// the summary card must not disagree about whether one exists.
    func testAFinishedReviewKeepsAConfidentBestShotEvenWhenScoresTurnAmbiguous() async {
        await repository.setStoredStates([clusterID: ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "b",
            isBestShotUserSelected: false,
            selectedLocalIdentifiers: [],
            isReviewConfirmed: true,
            status: .reviewed,
            estimatedSavingsBytes: 0
        )])
        let viewModel = makeViewModel(
            snapshots: weakClusterSnapshots,
            qualityScores: [("a", 4), ("b", 3.6), ("c", 3.8)]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "b")
        XCTAssertEqual(viewModel.bestShotConfidence, .automatic)
        XCTAssertTrue(viewModel.bestShotReasonCodes.isEmpty)
    }

    /// The badge belongs to the photo: a photo enhanced earlier keeps it after
    /// the screen is reopened, even once it is no longer the Best Shot.
    func testEnhancedBadgesAreRestoredFromTheScoreCache() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "sharp", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "enhanced", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            qualityScores: [("sharp", 60), ("enhanced", 20)],
            enhancedIdentifiers: ["enhanced"]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.bestShotAssetID, "sharp")
        XCTAssertTrue(viewModel.isEnhanced("enhanced"))
        XCTAssertFalse(viewModel.isEnhanced("sharp"))
    }

    /// Scoring can decode photos and fetch originals from iCloud. The screen
    /// must not wait for it: it appears on the metadata ranking and refines
    /// itself when the measurements land.
    func testTheScreenAppearsBeforeQualityScoringFinishes() async {
        let analyzer = StallingPhotoQualityAnalyzer()
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: analyzer,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }

        XCTAssertTrue(viewModel.hasLoadedReviewState)
        XCTAssertEqual(viewModel.bestShotAssetID, "favorite")

        await analyzer.finish(with: [])
        await loading.value
    }

    /// The star must not appear on one photo and hop to another once scoring
    /// lands: while the measured ranking is pending the badge stays hidden.
    func testTheBestShotBadgeWaitsForTheMeasuredRanking() async {
        let analyzer = StallingPhotoQualityAnalyzer()
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: analyzer,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }

        XCTAssertTrue(viewModel.isRankingQualityPending)
        XCTAssertFalse(viewModel.isBestShotVisible)

        let config = PhotoQualityScoringConfig.current
        await analyzer.finish(with: [
            PhotoQualityScore(
                localIdentifier: "plain",
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(globalSharpness: 80, subjectLumaStdDev: 0.25, pixelArea: 1_000)
            ),
            PhotoQualityScore(
                localIdentifier: "favorite",
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(globalSharpness: 10, subjectLumaStdDev: 0.25, pixelArea: 1_000)
            )
        ])
        await loading.value

        XCTAssertFalse(viewModel.isRankingQualityPending)
        XCTAssertTrue(viewModel.isBestShotVisible)
        XCTAssertEqual(viewModel.bestShotAssetID, "plain")
    }

    func testAnEmptyMeasurementStopsWaitingAndShowsTheMetadataPick() async {
        let analyzer = StallingPhotoQualityAnalyzer()
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: analyzer,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }
        await analyzer.finish(with: [])
        await loading.value

        XCTAssertFalse(viewModel.isRankingQualityPending)
        XCTAssertTrue(viewModel.isBestShotVisible)
        XCTAssertEqual(viewModel.bestShotAssetID, "favorite")
    }

    /// A ranking that arrives after the user has acted must not overwrite them.
    func testALateRankingDoesNotOverwriteTheUsersOwnPick() async {
        let analyzer = StallingPhotoQualityAnalyzer()
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: analyzer,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }
        viewModel.setBestShot("plain")

        let config = PhotoQualityScoringConfig.current
        await analyzer.finish(with: [
            PhotoQualityScore(
                localIdentifier: "plain",
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(globalSharpness: 5, subjectLumaStdDev: 0.25, pixelArea: 1_000)
            ),
            PhotoQualityScore(
                localIdentifier: "favorite",
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(globalSharpness: 80, subjectLumaStdDev: 0.25, pixelArea: 1_000)
            )
        ])
        await loading.value

        XCTAssertEqual(viewModel.bestShotAssetID, "plain")
        XCTAssertTrue(viewModel.isBestShotUserSelected)
    }

    /// `applyLoadedState`'s personalized config load (`await
    /// personalizedConfigProvider?.config()`) is itself a suspension point,
    /// and every observable property it is about to derive a ranking from —
    /// `assetSnapshots` included — must stay untouched until that load
    /// resolves. Before the fix these properties were written *before* the
    /// config await; a screen read landing in that window would have seen a
    /// half-applied ranking. This drives a real, suspendable
    /// `BestShotPersonalizedScoringConfigProvider` to pin the screen inside
    /// that exact window and checks nothing has leaked out yet.
    ///
    /// This exercises the *initial* `load()` call, where `expectedGeneration`
    /// is `nil` and the `interactionGeneration` guard is skipped entirely —
    /// the `setBestShot` below has nothing to act on yet (`assetSnapshots` is
    /// still empty) and simply no-ops. It does not prove that a manual pick
    /// survives a config load that resumes *after* the pick: that needs the
    /// generation guard to be live, which needs a second, independently
    /// suspendable config load — not reproducible here, because the concrete
    /// `BestShotPersonalizedScoringConfigProvider` caches for good after its
    /// first successful load, and that first load is the one this test is
    /// already holding open.
    func testNothingIsPublishedWhileThePersonalizedConfigIsStillLoading() async {
        let personalizationRepository = SuspendableLoadWeightsPersonalizationRepository()
        let personalizedConfigProvider = BestShotPersonalizedScoringConfigProvider(
            repository: personalizationRepository
        )
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            personalizedConfigProvider: personalizedConfigProvider,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }

        // `applyLoadedState` is suspended awaiting the personalized config —
        // before the fix, `assetSnapshots`/`bestShotAssetID` would already be
        // populated at this point.
        await personalizationRepository.waitUntilLoadStarted()
        XCTAssertFalse(viewModel.hasLoadedReviewState)
        XCTAssertEqual(viewModel.assetCount, 0)
        XCTAssertTrue(viewModel.bestShotAssetID.isEmpty)

        // A pick attempted in this window has nothing to act on yet — the
        // screen has not published anything an interaction could target —
        // and must not crash or leave the view model in a broken state.
        viewModel.setBestShot("plain")
        XCTAssertFalse(viewModel.isBestShotUserSelected)

        await personalizationRepository.resumeLoad()
        await loading.value

        // Once the config resolves, the ranking publishes normally, and
        // interactions work exactly as they would have without a
        // personalized config provider at all.
        XCTAssertTrue(viewModel.hasLoadedReviewState)
        XCTAssertEqual(viewModel.assetCount, 2)
        XCTAssertFalse(viewModel.bestShotAssetID.isEmpty)

        viewModel.setBestShot("plain")
        XCTAssertEqual(viewModel.bestShotAssetID, "plain")
        XCTAssertTrue(viewModel.isBestShotUserSelected)
    }

    /// The race the seam above exists for: a manual pick made while a
    /// *second*, later `config()` await is in flight — the one inside
    /// `refineWithQualityScores`'s call to `applyLoadedState` — must still
    /// win. This cannot be reproduced with the real
    /// `BestShotPersonalizedScoringConfigProvider`, whose cache is warm by
    /// the time a second call happens (see the test above); it needs a
    /// double whose first call passes straight through, so the initial,
    /// metadata-only ranking can land on screen, and whose second call parks
    /// on demand.
    func testAManualPickDuringARefiningConfigLoadIsNotOverwritten() async {
        let configProvider = SecondCallSuspendingConfigProvider()
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: StubPhotoQualityAnalyzer(
                sharpnessByIdentifier: [("plain", 5), ("favorite", 80)]
            ),
            personalizedConfigProvider: configProvider,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }

        // The initial `applyLoadedState`'s `config()` call (#1) passes
        // straight through, so the metadata-only ranking lands on screen...
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }
        XCTAssertFalse(viewModel.bestShotAssetID.isEmpty)

        // ...and the refine's `applyLoadedState` reaches its own `config()`
        // (call #2), which this double parks.
        await configProvider.waitUntilSecondCallStarted()

        // The user's manual pick, made while that second config load is
        // still in flight. `setBestShot` bumps `interactionGeneration`
        // synchronously, before this call resumes.
        viewModel.setBestShot("plain")
        XCTAssertEqual(viewModel.bestShotAssetID, "plain")
        XCTAssertTrue(viewModel.isBestShotUserSelected)

        await configProvider.resumeSecondCall()
        await loading.value

        // "favorite" is the sharper photo, so a refined ranking that ignored
        // the race would have promoted it here instead. It must not have.
        XCTAssertEqual(viewModel.bestShotAssetID, "plain")
        XCTAssertTrue(viewModel.isBestShotUserSelected)
    }

    private var weakClusterSnapshots: [ReviewAssetSnapshot] {
        [
            snapshot(id: "a", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
            snapshot(id: "b", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20)),
            snapshot(id: "c", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 30))
        ]
    }

    private func makeViewModel(
        snapshots: [ReviewAssetSnapshot],
        reviewRepository: (any ClusterReviewStateRepository)? = nil,
        cleanupHistoryRepository: (any CleanupHistoryRepository)? = nil,
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        qualityScores: [(String, Double)] = [],
        enhancedIdentifiers: Set<String> = [],
        overrideMetrics: (any BestShotOverrideMetricsRepository)? = nil,
        personalizedConfigProvider: BestShotPersonalizedScoringConfigProvider? = nil,
        completionDelay: @escaping @MainActor @Sendable () async -> Void = {}
    ) -> ClusterDetailsViewModel {
        ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: reviewRepository ?? repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository ?? self.cleanupHistoryRepository,
            premiumAccess: premiumAccess,
            qualityAnalyzer: StubPhotoQualityAnalyzer(
                sharpnessByIdentifier: qualityScores,
                enhancedIdentifiers: enhancedIdentifiers
            ),
            overrideMetrics: overrideMetrics,
            personalizedConfigProvider: personalizedConfigProvider,
            assetSnapshots: snapshots,
            completionDelay: completionDelay
        )
    }

    private func makeViewModel(
        loader: ControlledReviewAssetSnapshotLoader
    ) -> ClusterDetailsViewModel {
        ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            assetSnapshotLoader: { try await loader.load() },
            completionDelay: {}
        )
    }

    private func waitForPersistedRevision(
        _ expected: Int,
        on viewModel: ClusterDetailsViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 where viewModel.persistedRevision < expected {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.persistedRevision, expected, file: file, line: line)
    }

    private func snapshot(
        id: String,
        isFavorite: Bool,
        area: Int,
        createdAt: Date?,
        modifiedAt: Date? = nil
    ) -> ReviewAssetSnapshot {
        ReviewAssetSnapshot(
            localIdentifier: id,
            isFavorite: isFavorite,
            pixelWidth: area,
            pixelHeight: 1,
            creationDate: createdAt,
            modificationDate: modifiedAt
        )
    }
}

/// Returns fixed signals regardless of the assets it is handed: the cluster
/// under test has snapshots, not live `PHAsset`s.
private struct StubPhotoQualityAnalyzer: PhotoQualityAnalyzing {
    let sharpnessByIdentifier: [(String, Double)]
    var enhancedIdentifiers: Set<String> = []

    func scores(for _: [PHAsset]) async throws -> [PhotoQualityScore] {
        let config = PhotoQualityScoringConfig.current
        return sharpnessByIdentifier.map { identifier, sharpness in
            PhotoQualityScore(
                localIdentifier: identifier,
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(
                    globalSharpness: sharpness,
                    subjectLumaStdDev: 0.25,
                    noiseEstimate: 0.1,
                    pixelArea: 1_000
                ),
                isAlikeEnhanced: enhancedIdentifiers.contains(identifier)
            )
        }
    }
}

/// Returns caller-supplied signals verbatim, for tests that need control over
/// more than just sharpness (exposure, noise, faces).
private struct StubSignalsPhotoQualityAnalyzer: PhotoQualityAnalyzing {
    let signalsByIdentifier: [String: PhotoQualitySignals]

    func scores(for _: [PHAsset]) async throws -> [PhotoQualityScore] {
        let config = PhotoQualityScoringConfig.current
        return signalsByIdentifier.map { identifier, signals in
            PhotoQualityScore(
                localIdentifier: identifier,
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: signals,
                isAlikeEnhanced: false
            )
        }
    }
}

/// Holds the scoring call open until the test decides to answer it.
private actor StallingPhotoQualityAnalyzer: PhotoQualityAnalyzing {
    private var continuation: CheckedContinuation<[PhotoQualityScore], Never>?
    private var pending: [PhotoQualityScore]?

    func scores(for _: [PHAsset]) async throws -> [PhotoQualityScore] {
        if let pending {
            self.pending = nil
            return pending
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(with scores: [PhotoQualityScore]) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: scores)
        } else {
            pending = scores
        }
    }
}

private actor ControlledReviewAssetSnapshotLoader {
    let snapshots: [ReviewAssetSnapshot]
    private(set) var invocationCount = 0
    private var didStart = false
    private var isFinished = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    init(snapshots: [ReviewAssetSnapshot]) {
        self.snapshots = snapshots
    }

    func load() async throws -> [ReviewAssetSnapshot] {
        invocationCount += 1
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isFinished {
                    continuation.resume()
                } else {
                    finishContinuation = continuation
                }
            }
        } onCancel: {
            Task { await self.finish() }
        }

        try Task.checkCancellation()
        return snapshots
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

private actor SuspendedClusterCleanupCompletionDelay {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didStart = false

    func wait() async {
        didStart = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !didStart {
            await Task.yield()
        }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

/// A `BestShotPersonalizationRepository` whose `loadWeights()` suspends until
/// `resumeLoad()` is called, so tests can drive the personalized config load
/// inside `applyLoadedState` open at an exact point.
private actor SuspendableLoadWeightsPersonalizationRepository: BestShotPersonalizationRepository {
    private var loadStarted = false
    private var continuation: CheckedContinuation<BestShotPersonalWeights?, Never>?

    func loadExamples() async -> [BestShotOverrideExample] { [] }

    func record(_ example: BestShotOverrideExample) async {}

    func loadWeights() async -> BestShotPersonalWeights? {
        loadStarted = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func saveWeights(_ weights: BestShotPersonalWeights) async {}

    func clearWeights() async {}

    func reset() async {}

    func waitUntilLoadStarted() async {
        while !loadStarted {
            await Task.yield()
        }
    }

    func resumeLoad(with weights: BestShotPersonalWeights? = nil) {
        continuation?.resume(returning: weights)
        continuation = nil
    }
}

/// A `BestShotConfigProviding` whose `config()` passes straight through on
/// its first call — so an initial, metadata-only ranking can land on screen —
/// and suspends on every call after that until `resumeSecondCall()` runs.
/// The concrete `BestShotPersonalizedScoringConfigProvider` cannot stand in
/// for this: its cache is warm by the time a second `config()` call happens,
/// so it can only ever be held open on its *first* call, before there is
/// anything on screen for a manual pick to act on. This double is the only
/// way to pin a caller inside a *later* `config()` await.
private actor SecondCallSuspendingConfigProvider: BestShotConfigProviding {
    private var callCount = 0
    private(set) var secondCallStarted = false
    private var continuation: CheckedContinuation<Void, Never>?

    func config() async -> PhotoQualityScoringConfig {
        callCount += 1
        guard callCount > 1 else { return .current }
        secondCallStarted = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return .current
    }

    func recordOverride(_ example: BestShotOverrideExample) async {}

    func waitUntilSecondCallStarted() async {
        while !secondCallStarted {
            await Task.yield()
        }
    }

    func resumeSecondCall() {
        continuation?.resume()
        continuation = nil
    }
}

private actor SuspendableSaveClusterReviewStateRepository: ClusterReviewStateRepository {
    private var states: [UUID: ClusterReviewState] = [:]
    private var saveCount = 0
    private var shouldSuspendNextSave = false
    private var suspendedSaveStarted = false
    private var saveContinuation: CheckedContinuation<Void, Never>?

    func loadReviewState(clusterID: UUID) async throws -> ClusterReviewState? {
        states[clusterID]
    }

    func loadAllReviewStates() async throws -> [UUID: ClusterReviewState] {
        states
    }

    func saveReviewState(_ state: ClusterReviewState) async throws {
        if shouldSuspendNextSave {
            shouldSuspendNextSave = false
            suspendedSaveStarted = true
            await withCheckedContinuation { continuation in
                saveContinuation = continuation
            }
        }
        states[state.clusterID] = state
        saveCount += 1
    }

    func deleteReviewState(clusterID: UUID) async throws {
        states.removeValue(forKey: clusterID)
    }

    func deleteAllReviewStates() async throws {
        states.removeAll()
    }

    func suspendNextSave() {
        shouldSuspendNextSave = true
        suspendedSaveStarted = false
    }

    func waitUntilSaveCount(_ expectedCount: Int) async {
        while saveCount < expectedCount {
            await Task.yield()
        }
    }

    func waitUntilSuspendedSaveStarts() async {
        while !suspendedSaveStarted {
            await Task.yield()
        }
    }

    func finishSuspendedSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }

    func storedState(clusterID: UUID) -> ClusterReviewState? {
        states[clusterID]
    }
}

private actor SuspendedClusterReviewStateRepository: ClusterReviewStateRepository {
    private var states: [UUID: ClusterReviewState]
    private var deleteContinuation: CheckedContinuation<Void, Never>?
    private var deleteStarted = false

    init(state: ClusterReviewState) {
        self.states = [state.clusterID: state]
    }

    func loadReviewState(clusterID: UUID) async throws -> ClusterReviewState? {
        states[clusterID]
    }

    func loadAllReviewStates() async throws -> [UUID: ClusterReviewState] {
        states
    }

    func saveReviewState(_ state: ClusterReviewState) async throws {
        states[state.clusterID] = state
    }

    func deleteReviewState(clusterID: UUID) async throws {
        deleteStarted = true
        await withCheckedContinuation { continuation in
            deleteContinuation = continuation
        }
        states.removeValue(forKey: clusterID)
    }

    func deleteAllReviewStates() async throws {
        states.removeAll()
    }

    func waitUntilDeleteStarts() async {
        while !deleteStarted {
            await Task.yield()
        }
    }

    func finishDelete() {
        deleteContinuation?.resume()
        deleteContinuation = nil
    }
}
