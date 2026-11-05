import Foundation
import Testing
import Core
import Photos
@testable import Details

@MainActor
@Suite struct ClusterDetailsViewModelHapticsTests: ClusterDetailsViewModelFixture {
    let repository = MockClusterReviewStateRepository()
    let cleanupService = MockPhotoCleanupService()
    let cleanupHistoryRepository = MockCleanupHistoryRepository()
    let clusterID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

    // MARK: - Haptic feedback triggers

    /// The double haptic on open: the metadata ranking named one photo, the
    /// measured one named another, and the feedback followed the value rather
    /// than the user.
    @Test func testOpeningAClusterWhoseRankingMovesTheBestShotFiresNoFeedback() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "blurred-favorite", isFavorite: true, area: 4_000, createdAt: Date(timeIntervalSince1970: 20)),
                snapshot(id: "sharp", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10))
            ],
            qualityScores: [("blurred-favorite", 12), ("sharp", 60)]
        )

        await viewModel.load()

        #expect(viewModel.bestShotAssetID == "sharp", "the ranking must still move the pick")
        #expect(viewModel.successFeedbackTrigger == 0)
        #expect(viewModel.selectionFeedbackTrigger == 0)
    }

    @Test func testOpeningAReviewedClusterWithARestoredSelectionFiresNoFeedback() async {
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

        #expect(viewModel.reviewStatus == .reviewed)
        #expect(viewModel.selectedAssetIDs == ["sharper"])
        #expect(viewModel.successFeedbackTrigger == 0)
        #expect(viewModel.selectionFeedbackTrigger == 0)
    }

    @Test func testChoosingTheBestShotFiresOneSuccessFeedbackOnly() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "a", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "b", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ]
        )
        await viewModel.load()

        viewModel.setBestShot("b")

        #expect(viewModel.successFeedbackTrigger == 1)
        #expect(viewModel.selectionFeedbackTrigger == 0, "a Best Shot pick is one action, not two patterns")

        // Re-picking the photo that is already the Best Shot changes nothing.
        viewModel.setBestShot("b")
        #expect(viewModel.successFeedbackTrigger == 1)
    }

    @Test func testSelectingAPhotoFiresOneSelectionFeedbackOnly() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "other", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ]
        )
        await viewModel.load()

        viewModel.toggleSelection(for: "other")

        #expect(viewModel.selectionFeedbackTrigger == 1)
        #expect(viewModel.successFeedbackTrigger == 0)

        // A rejected toggle — the Best Shot is always kept — is not an action.
        viewModel.toggleSelection(for: viewModel.bestShotAssetID)
        #expect(viewModel.selectionFeedbackTrigger == 1)
    }

    @Test func testFinishingTheReviewFiresOneSuccessFeedbackAndReopeningItFiresNone() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "other", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20))
            ]
        )
        await viewModel.load()

        viewModel.toggleReviewConfirmation()
        #expect(viewModel.reviewStatus == .reviewed)
        #expect(viewModel.successFeedbackTrigger == 1)

        viewModel.toggleReviewConfirmation()
        #expect(viewModel.reviewStatus != .reviewed)
        #expect(viewModel.successFeedbackTrigger == 1, "reopening a review is not a confirmation")
    }
}
