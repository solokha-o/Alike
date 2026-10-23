import XCTest
import Core
@testable import Details

/// A swipe on a photo tile must be the tile's own tap or context-menu action,
/// not a second way to change review state. Each test drives one view model
/// through the existing button path and a twin through the swipe, then
/// compares what the screen shows, what drives its haptics, and what was saved.
@MainActor
final class PhotoTileSwipeActionsTests: XCTestCase {
    private let clusterID = UUID(uuidString: "00000000-0000-0000-0000-000000000027")!

    // MARK: - Offered actions

    func testUnselectedTileOffersSelectAndMakeBestShot() throws {
        try requireSwipeSupport()
        let actions = PhotoTileSwipeAction.available(
            isSelected: false, isBestShot: false, canSelect: true, canMakeBestShot: true
        )
        XCTAssertEqual(actions, [.select, .makeBestShot])
        XCTAssertEqual(PhotoTileSwipeAction.select.edge, .trailing)
        XCTAssertEqual(PhotoTileSwipeAction.makeBestShot.edge, .leading)
    }

    func testSelectedTileOffersKeepInsteadOfSelect() throws {
        try requireSwipeSupport()
        let actions = PhotoTileSwipeAction.available(
            isSelected: true, isBestShot: false, canSelect: true, canMakeBestShot: true
        )
        XCTAssertEqual(actions, [.keep, .makeBestShot])
        XCTAssertEqual(PhotoTileSwipeAction.keep.edge, .leading)
    }

    func testBestShotTileOffersNothing() throws {
        try requireSwipeSupport()
        let actions = PhotoTileSwipeAction.available(
            isSelected: false, isBestShot: true, canSelect: true, canMakeBestShot: true
        )
        XCTAssertEqual(actions, [])
    }

    func testWithoutBestShotNothingIsSelectable() throws {
        try requireSwipeSupport()
        let actions = PhotoTileSwipeAction.available(
            isSelected: false, isBestShot: false, canSelect: false, canMakeBestShot: true
        )
        XCTAssertEqual(actions, [.makeBestShot])
    }

    func testScreenshotTileOffersOnlySelectionActions() throws {
        try requireSwipeSupport()
        XCTAssertEqual(
            PhotoTileSwipeAction.available(
                isSelected: false, isBestShot: false, canSelect: true, canMakeBestShot: false
            ),
            [.select]
        )
        XCTAssertEqual(
            PhotoTileSwipeAction.available(
                isSelected: true, isBestShot: false, canSelect: true, canMakeBestShot: false
            ),
            [.keep]
        )
    }

    // MARK: - Cluster review: swipe = button

    func testSwipeSelectMatchesTileTap() async {
        let (tapped, tappedRepository) = await loadedClusterViewModel()
        let (swiped, swipedRepository) = await loadedClusterViewModel()

        tapped.toggleSelection(for: "candidate")
        PhotoTileSwipeAction.select.perform(on: swiped, assetID: "candidate")

        XCTAssertEqual(swiped.selectedAssetIDs, ["candidate"])
        await assertSameReviewState(tapped, tappedRepository, swiped, swipedRepository)
    }

    func testSwipeKeepMatchesTileTapOnSelectedPhoto() async {
        let (tapped, tappedRepository) = await loadedClusterViewModel(selected: ["candidate"])
        let (swiped, swipedRepository) = await loadedClusterViewModel(selected: ["candidate"])

        tapped.toggleSelection(for: "candidate")
        PhotoTileSwipeAction.keep.perform(on: swiped, assetID: "candidate")

        XCTAssertEqual(swiped.selectedAssetIDs, [])
        await assertSameReviewState(tapped, tappedRepository, swiped, swipedRepository)
    }

    func testSwipeMakeBestShotMatchesContextMenu() async {
        let (tapped, tappedRepository) = await loadedClusterViewModel()
        let (swiped, swipedRepository) = await loadedClusterViewModel()

        tapped.setBestShot("candidate")
        PhotoTileSwipeAction.makeBestShot.perform(on: swiped, assetID: "candidate")

        XCTAssertEqual(swiped.bestShotAssetID, "candidate")
        XCTAssertEqual(swiped.successFeedbackTrigger, tapped.successFeedbackTrigger)
        await assertSameReviewState(tapped, tappedRepository, swiped, swipedRepository)
    }

    /// A swipe that lands after the photo already changed side must not flip it back.
    func testSelectOnSelectedPhotoAndKeepOnKeptPhotoChangeNothing() async {
        let (viewModel, _) = await loadedClusterViewModel(selected: ["candidate"])
        let feedback = viewModel.selectionFeedbackTrigger

        PhotoTileSwipeAction.select.perform(on: viewModel, assetID: "candidate")
        XCTAssertEqual(viewModel.selectedAssetIDs, ["candidate"])

        PhotoTileSwipeAction.keep.perform(on: viewModel, assetID: "other")
        XCTAssertEqual(viewModel.selectedAssetIDs, ["candidate"])
        XCTAssertEqual(viewModel.selectionFeedbackTrigger, feedback)
    }

    func testSwipeSelectCannotSelectTheBestShot() async {
        let (viewModel, _) = await loadedClusterViewModel()

        PhotoTileSwipeAction.select.perform(on: viewModel, assetID: "best")

        XCTAssertEqual(viewModel.selectedAssetIDs, [])
    }

    // MARK: - Screenshot cleanup: swipe = button

    func testScreenshotSwipeSelectAndKeepMatchTileTap() {
        let tapped = makeScreenshotViewModel()
        let swiped = makeScreenshotViewModel()

        tapped.toggleSelection(for: "one")
        PhotoTileSwipeAction.select.perform(on: swiped, assetID: "one")
        XCTAssertEqual(swiped.selectedAssetIDs, tapped.selectedAssetIDs)
        XCTAssertEqual(swiped.estimatedSavingsBytes, tapped.estimatedSavingsBytes)
        XCTAssertEqual(swiped.isDeleteActionVisible, tapped.isDeleteActionVisible)

        tapped.toggleSelection(for: "one")
        PhotoTileSwipeAction.keep.perform(on: swiped, assetID: "one")
        XCTAssertEqual(swiped.selectedAssetIDs, [])
        XCTAssertEqual(swiped.selectedAssetIDs, tapped.selectedAssetIDs)
        XCTAssertEqual(swiped.estimatedSavingsBytes, tapped.estimatedSavingsBytes)
    }

    func testScreenshotSwipeMakeBestShotDoesNothing() {
        let viewModel = makeScreenshotViewModel()

        PhotoTileSwipeAction.makeBestShot.perform(on: viewModel, assetID: "one")

        XCTAssertEqual(viewModel.selectedAssetIDs, [])
    }

    // MARK: - Helpers

    private func requireSwipeSupport() throws {
        guard PhotoTileSwipeAction.isSupported else {
            throw XCTSkip("Grid swipe actions need iOS 27.")
        }
    }

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
                clusterSnapshot(id: "other", area: 300)
            ],
            completionDelay: {}
        )
        await viewModel.load()
        XCTAssertEqual(viewModel.bestShotAssetID, "best")
        XCTAssertEqual(viewModel.selectedAssetIDs, selected)
        return (viewModel, repository)
    }

    private func assertSameReviewState(
        _ tapped: ClusterDetailsViewModel,
        _ tappedRepository: MockClusterReviewStateRepository,
        _ swiped: ClusterDetailsViewModel,
        _ swipedRepository: MockClusterReviewStateRepository,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        XCTAssertEqual(swiped.selectedAssetIDs, tapped.selectedAssetIDs, file: file, line: line)
        XCTAssertEqual(swiped.bestShotAssetID, tapped.bestShotAssetID, file: file, line: line)
        XCTAssertEqual(swiped.reviewStatus, tapped.reviewStatus, file: file, line: line)
        XCTAssertEqual(swiped.isReviewConfirmed, tapped.isReviewConfirmed, file: file, line: line)
        XCTAssertEqual(swiped.estimatedSavingsText, tapped.estimatedSavingsText, file: file, line: line)
        // The same triggers drive the screen's `sensoryFeedback`, so equal
        // counters mean equal haptics.
        XCTAssertEqual(swiped.selectionFeedbackTrigger, tapped.selectionFeedbackTrigger, file: file, line: line)
        XCTAssertEqual(swiped.successFeedbackTrigger, tapped.successFeedbackTrigger, file: file, line: line)

        await tapped.awaitPendingPersistence()
        await swiped.awaitPendingPersistence()
        XCTAssertEqual(swiped.persistedRevision, tapped.persistedRevision, file: file, line: line)
        let tappedState = await tappedRepository.storedStates[clusterID]
        let swipedState = await swipedRepository.storedStates[clusterID]
        XCTAssertNotNil(swipedState, file: file, line: line)
        XCTAssertEqual(swipedState?.bestShotLocalIdentifier, tappedState?.bestShotLocalIdentifier, file: file, line: line)
        XCTAssertEqual(swipedState?.isBestShotUserSelected, tappedState?.isBestShotUserSelected, file: file, line: line)
        XCTAssertEqual(swipedState?.selectedLocalIdentifiers, tappedState?.selectedLocalIdentifiers, file: file, line: line)
        XCTAssertEqual(swipedState?.isReviewConfirmed, tappedState?.isReviewConfirmed, file: file, line: line)
        XCTAssertEqual(swipedState?.mode, tappedState?.mode, file: file, line: line)
        XCTAssertEqual(swipedState?.status, tappedState?.status, file: file, line: line)
        XCTAssertEqual(swipedState?.estimatedSavingsBytes, tappedState?.estimatedSavingsBytes, file: file, line: line)
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
                clusterSnapshot(id: "two", area: 100)
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
