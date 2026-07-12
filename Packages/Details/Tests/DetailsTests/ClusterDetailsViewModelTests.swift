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
        XCTAssertEqual(viewModel.reviewStatus, .reviewed)
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
        XCTAssertEqual(viewModel.reviewStatus, .reviewed)
    }

    func testKeepBestOnlySelectsAllNonBestAssets() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.keepBestOnly()

        XCTAssertEqual(viewModel.selectedAssetIDs, ["one"])
        XCTAssertEqual(viewModel.reviewStatus, .reviewed)
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
        XCTAssertEqual(viewModel.reviewStatus, .inReview)
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

    func testKeepBestOnlyShowsOnlyBestShotInGridMode() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.keepBestOnly()

        XCTAssertEqual(viewModel.displayedAssetIdentifiers, ["best"])
        XCTAssertEqual(viewModel.selectedAssetIDs, ["one", "two"])
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
        XCTAssertFalse(viewModel.isDeleting)
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
        XCTAssertEqual(viewModel.deleteErrorMessage, "Couldn't delete the selected photos. Please try again.")
        XCTAssertFalse(viewModel.isDeleting)
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
        XCTAssertEqual(viewModel.deleteErrorMessage, "Select at least one photo before deleting.")
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

    private func makeViewModel(
        snapshots: [ReviewAssetSnapshot],
        reviewRepository: (any ClusterReviewStateRepository)? = nil,
        cleanupHistoryRepository: (any CleanupHistoryRepository)? = nil,
        premiumAccess: any PremiumAccessControlling = PremiumAccessController()
    ) -> ClusterDetailsViewModel {
        ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: reviewRepository ?? repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository ?? self.cleanupHistoryRepository,
            premiumAccess: premiumAccess,
            assetSnapshots: snapshots
        )
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
