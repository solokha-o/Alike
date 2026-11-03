import XCTest
import Core
import Photos
@testable import Details

@MainActor
final class ClusterDetailsViewModelScoringTests: XCTestCase, ClusterDetailsViewModelFixture {
    let repository = MockClusterReviewStateRepository()
    let cleanupService = MockPhotoCleanupService()
    let cleanupHistoryRepository = MockCleanupHistoryRepository()
    let clusterID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

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
}
