import XCTest
import Core
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
        XCTAssertEqual(viewModel.deleteErrorMessage, DetailsL10n.Common.couldntDeleteSelectedPhotosPlease)
        XCTAssertEqual(
            viewModel.currentAlikeReaction?.state,
            .recoverableError(AlikeErrorContext(operation: .cleanup))
        )
        XCTAssertFalse(viewModel.isDeleting)

        viewModel.clearDeleteError()

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
        XCTAssertEqual(viewModel.deleteErrorMessage, DetailsL10n.Common.selectAtLeastOnePhoto)
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

        XCTAssertTrue(viewModel.isDeleteErrorPresented)

        viewModel.isDeleteErrorPresented = false

        XCTAssertFalse(viewModel.isDeleteErrorPresented)
        XCTAssertNil(viewModel.deleteErrorMessage)
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

        XCTAssertEqual(viewModel.deleteConfirmationTitle, DetailsL10n.ClusterDetails.move1SelectedPhotoRecently)
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
            String(format: DetailsL10n.ClusterDetails.moveSelectedPhotosRecentlyDeleted, 2)
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

    private func makeViewModel(
        snapshots: [ReviewAssetSnapshot],
        reviewRepository: (any ClusterReviewStateRepository)? = nil,
        cleanupHistoryRepository: (any CleanupHistoryRepository)? = nil,
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        completionDelay: @escaping @MainActor @Sendable () async -> Void = {}
    ) -> ClusterDetailsViewModel {
        ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: reviewRepository ?? repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository ?? self.cleanupHistoryRepository,
            premiumAccess: premiumAccess,
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
