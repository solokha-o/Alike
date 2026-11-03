import XCTest
import Core
import Photos
@testable import Details

@MainActor
final class ClusterDetailsViewModelCleanupTests: XCTestCase, ClusterDetailsViewModelFixture {
    let repository = MockClusterReviewStateRepository()
    let cleanupService = MockPhotoCleanupService()
    let cleanupHistoryRepository = MockCleanupHistoryRepository()
    let clusterID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

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
