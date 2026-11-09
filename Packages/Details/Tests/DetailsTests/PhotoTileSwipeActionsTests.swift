import Core
import Foundation
import Testing
@testable import Details

/// A swipe on a photo tile must be the tile's own tap or context-menu action,
/// not a second way to change review state. Each test drives one view model
/// through the existing button path and a twin through the swipe, then
/// compares what the screen shows, what drives its haptics, and what was saved.
@MainActor
struct PhotoTileSwipeActionsTests {
    private let clusterID = UUID(uuidString: "00000000-0000-0000-0000-000000000027")!

    // MARK: - Offered actions

    @Test(.enabled(if: PhotoTileSwipeAction.isSupported)) func testUnselectedTileOffersSelectAndMakeBestShot() {
        let actions = PhotoTileSwipeAction.available(
            isSelected: false, isBestShot: false, canSelect: true, canMakeBestShot: true
        )
        #expect(actions == [.select, .makeBestShot])
        #expect(PhotoTileSwipeAction.select.edge == .trailing)
        #expect(PhotoTileSwipeAction.makeBestShot.edge == .leading)
    }

    @Test(.enabled(if: PhotoTileSwipeAction.isSupported)) func testSelectedTileOffersKeepInsteadOfSelect() {
        let actions = PhotoTileSwipeAction.available(
            isSelected: true, isBestShot: false, canSelect: true, canMakeBestShot: true
        )
        #expect(actions == [.keep, .makeBestShot])
        #expect(PhotoTileSwipeAction.keep.edge == .leading)
    }

    @Test(.enabled(if: PhotoTileSwipeAction.isSupported)) func testBestShotTileOffersNothing() {
        let actions = PhotoTileSwipeAction.available(
            isSelected: false, isBestShot: true, canSelect: true, canMakeBestShot: true
        )
        #expect(actions == [])
    }

    @Test(.enabled(if: PhotoTileSwipeAction.isSupported)) func testWithoutBestShotNothingIsSelectable() {
        let actions = PhotoTileSwipeAction.available(
            isSelected: false, isBestShot: false, canSelect: false, canMakeBestShot: true
        )
        #expect(actions == [.makeBestShot])
    }

    @Test(.enabled(if: PhotoTileSwipeAction.isSupported)) func testScreenshotTileOffersOnlySelectionActions() {
        #expect(PhotoTileSwipeAction.available(
            isSelected: false, isBestShot: false, canSelect: true, canMakeBestShot: false
        ) == [.select])
        #expect(PhotoTileSwipeAction.available(
            isSelected: true, isBestShot: false, canSelect: true, canMakeBestShot: false
        ) == [.keep])
    }

    // MARK: - Edges

    /// An edge with no action must not get `swipeActions`: an empty edge still
    /// opens, and the tile sticks off its place.
    @Test(.enabled(if: PhotoTileSwipeAction.isSupported)) func testTileWithoutBestShotInTheClusterHasNothingOnTheTrailingEdge() {
        let actions = PhotoTileSwipeAction.available(
            isSelected: false, isBestShot: false, canSelect: false, canMakeBestShot: true
        )
        #expect(PhotoTileSwipeAction.actions(actions, on: .leading) == [.makeBestShot])
        #expect(PhotoTileSwipeAction.actions(actions, on: .trailing) == [])
    }

    @Test(.enabled(if: PhotoTileSwipeAction.isSupported)) func testUnselectedTileHasAnActionOnEachEdge() {
        let actions = PhotoTileSwipeAction.available(
            isSelected: false, isBestShot: false, canSelect: true, canMakeBestShot: true
        )
        #expect(PhotoTileSwipeAction.actions(actions, on: .leading) == [.makeBestShot])
        #expect(PhotoTileSwipeAction.actions(actions, on: .trailing) == [.select])
    }

    @Test(.enabled(if: PhotoTileSwipeAction.isSupported)) func testSelectedTileHasNothingOnTheTrailingEdge() {
        let actions = PhotoTileSwipeAction.available(
            isSelected: true, isBestShot: false, canSelect: true, canMakeBestShot: true
        )
        #expect(PhotoTileSwipeAction.actions(actions, on: .leading) == [.keep, .makeBestShot])
        #expect(PhotoTileSwipeAction.actions(actions, on: .trailing) == [])
    }

    // MARK: - Cluster review: swipe = button

    @Test func testSwipeSelectMatchesTileTap() async {
        let (tapped, tappedRepository) = await loadedClusterViewModel()
        let (swiped, swipedRepository) = await loadedClusterViewModel()

        tapped.toggleSelection(for: "candidate")
        PhotoTileSwipeAction.select.perform(on: swiped, assetID: "candidate")

        #expect(swiped.selectedAssetIDs == ["candidate"])
        await assertSameReviewState(tapped, tappedRepository, swiped, swipedRepository)
    }

    @Test func testSwipeKeepMatchesTileTapOnSelectedPhoto() async {
        let (tapped, tappedRepository) = await loadedClusterViewModel(selected: ["candidate"])
        let (swiped, swipedRepository) = await loadedClusterViewModel(selected: ["candidate"])

        tapped.toggleSelection(for: "candidate")
        PhotoTileSwipeAction.keep.perform(on: swiped, assetID: "candidate")

        #expect(swiped.selectedAssetIDs == [])
        await assertSameReviewState(tapped, tappedRepository, swiped, swipedRepository)
    }

    @Test func testSwipeMakeBestShotMatchesContextMenu() async {
        let (tapped, tappedRepository) = await loadedClusterViewModel()
        let (swiped, swipedRepository) = await loadedClusterViewModel()

        tapped.setBestShot("candidate")
        PhotoTileSwipeAction.makeBestShot.perform(on: swiped, assetID: "candidate")

        #expect(swiped.bestShotAssetID == "candidate")
        #expect(swiped.successFeedbackTrigger == tapped.successFeedbackTrigger)
        await assertSameReviewState(tapped, tappedRepository, swiped, swipedRepository)
    }

    /// A swipe that lands after the photo already changed side must not flip it back.
    @Test func testSelectOnSelectedPhotoAndKeepOnKeptPhotoChangeNothing() async {
        let (viewModel, _) = await loadedClusterViewModel(selected: ["candidate"])
        let feedback = viewModel.selectionFeedbackTrigger

        PhotoTileSwipeAction.select.perform(on: viewModel, assetID: "candidate")
        #expect(viewModel.selectedAssetIDs == ["candidate"])

        PhotoTileSwipeAction.keep.perform(on: viewModel, assetID: "other")
        #expect(viewModel.selectedAssetIDs == ["candidate"])
        #expect(viewModel.selectionFeedbackTrigger == feedback)
    }

    @Test func testSwipeSelectCannotSelectTheBestShot() async {
        let (viewModel, _) = await loadedClusterViewModel()

        PhotoTileSwipeAction.select.perform(on: viewModel, assetID: "best")

        #expect(viewModel.selectedAssetIDs == [])
    }

    // MARK: - Screenshot cleanup: swipe = button

    @Test func testScreenshotSwipeSelectAndKeepMatchTileTap() {
        let tapped = makeScreenshotViewModel()
        let swiped = makeScreenshotViewModel()

        tapped.toggleSelection(for: "one")
        PhotoTileSwipeAction.select.perform(on: swiped, assetID: "one")
        #expect(swiped.selectedAssetIDs == tapped.selectedAssetIDs)
        #expect(swiped.estimatedSavingsBytes == tapped.estimatedSavingsBytes)
        #expect(swiped.isDeleteActionVisible == tapped.isDeleteActionVisible)

        tapped.toggleSelection(for: "one")
        PhotoTileSwipeAction.keep.perform(on: swiped, assetID: "one")
        #expect(swiped.selectedAssetIDs == [])
        #expect(swiped.selectedAssetIDs == tapped.selectedAssetIDs)
        #expect(swiped.estimatedSavingsBytes == tapped.estimatedSavingsBytes)
    }

    @Test func testScreenshotSwipeMakeBestShotDoesNothing() {
        let viewModel = makeScreenshotViewModel()

        PhotoTileSwipeAction.makeBestShot.perform(on: viewModel, assetID: "one")

        #expect(viewModel.selectedAssetIDs == [])
    }

    // MARK: - Helpers

    private func loadedClusterViewModel(
        selected: Set<String> = []
    ) async -> (ClusterDetailsViewModel, MockClusterReviewStateRepository) {
        let repository = MockClusterReviewStateRepository()
        await repository.setStoredStates([clusterID: ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: selected,
            mode: .selection,
            status: .inReview,
            estimatedSavingsBytes: 0
        )])
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: MockPhotoCleanupService(),
            cleanupHistoryRepository: MockCleanupHistoryRepository(),
            premiumAccess: PremiumAccessController(),
            assetSnapshots: [
                clusterSnapshot(id: "best", area: 900),
                clusterSnapshot(id: "candidate", area: 500),
                clusterSnapshot(id: "other", area: 300),
            ],
            completionDelay: {}
        )
        await viewModel.load()
        #expect(viewModel.bestShotAssetID == "best")
        #expect(viewModel.selectedAssetIDs == selected)
        return (viewModel, repository)
    }

    private func assertSameReviewState(
        _ tapped: ClusterDetailsViewModel,
        _ tappedRepository: MockClusterReviewStateRepository,
        _ swiped: ClusterDetailsViewModel,
        _ swipedRepository: MockClusterReviewStateRepository,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        #expect(swiped.selectedAssetIDs == tapped.selectedAssetIDs, sourceLocation: sourceLocation)
        #expect(swiped.bestShotAssetID == tapped.bestShotAssetID, sourceLocation: sourceLocation)
        #expect(swiped.reviewStatus == tapped.reviewStatus, sourceLocation: sourceLocation)
        #expect(swiped.isReviewConfirmed == tapped.isReviewConfirmed, sourceLocation: sourceLocation)
        #expect(swiped.estimatedSavingsText == tapped.estimatedSavingsText, sourceLocation: sourceLocation)
        // The same triggers drive the screen's `sensoryFeedback`, so equal
        // counters mean equal haptics.
        #expect(swiped.selectionFeedbackTrigger == tapped.selectionFeedbackTrigger, sourceLocation: sourceLocation)
        #expect(swiped.successFeedbackTrigger == tapped.successFeedbackTrigger, sourceLocation: sourceLocation)

        await tapped.awaitPendingPersistence()
        await swiped.awaitPendingPersistence()
        #expect(swiped.persistedRevision == tapped.persistedRevision, sourceLocation: sourceLocation)
        let tappedState = await tappedRepository.storedStates[clusterID]
        let swipedState = await swipedRepository.storedStates[clusterID]
        #expect(swipedState != nil, sourceLocation: sourceLocation)
        #expect(swipedState?.bestShotLocalIdentifier == tappedState?.bestShotLocalIdentifier, sourceLocation: sourceLocation)
        #expect(swipedState?.isBestShotUserSelected == tappedState?.isBestShotUserSelected, sourceLocation: sourceLocation)
        #expect(swipedState?.selectedLocalIdentifiers == tappedState?.selectedLocalIdentifiers, sourceLocation: sourceLocation)
        #expect(swipedState?.isReviewConfirmed == tappedState?.isReviewConfirmed, sourceLocation: sourceLocation)
        #expect(swipedState?.mode == tappedState?.mode, sourceLocation: sourceLocation)
        #expect(swipedState?.status == tappedState?.status, sourceLocation: sourceLocation)
        #expect(swipedState?.estimatedSavingsBytes == tappedState?.estimatedSavingsBytes, sourceLocation: sourceLocation)
    }

    private func makeScreenshotViewModel() -> ScreenshotCleanupViewModel {
        ScreenshotCleanupViewModel(
            assets: [],
            sourceCategory: .screenshots,
            cleanupService: MockPhotoCleanupService(),
            cleanupHistoryRepository: MockCleanupHistoryRepository(),
            premiumAccess: PremiumAccessController(),
            assetSnapshots: [
                clusterSnapshot(id: "one", area: 200),
                clusterSnapshot(id: "two", area: 100),
            ],
            completionDelay: {}
        )
    }

    private func clusterSnapshot(id: String, area: Int) -> ReviewAssetSnapshot {
        ReviewAssetSnapshot(
            localIdentifier: id,
            isFavorite: false,
            pixelWidth: area,
            pixelHeight: 1,
            creationDate: nil,
            modificationDate: nil
        )
    }
}
