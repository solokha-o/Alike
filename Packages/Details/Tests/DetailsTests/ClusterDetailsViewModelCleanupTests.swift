import Foundation
import Testing
import Core
import Photos
@testable import Details

@MainActor
@Suite struct ClusterDetailsViewModelCleanupTests: ClusterDetailsViewModelFixture {
    let repository = MockClusterReviewStateRepository()
    let cleanupService = MockPhotoCleanupService()
    let cleanupHistoryRepository = MockCleanupHistoryRepository()
    let clusterID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

    @Test func testConfirmDeleteCallsCleanupServiceAndPersistsHistory() async throws {
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

        #expect(cleanupDidRun)
        #expect(lastSelection == Set(["one", "two"]))
        #expect(storedEntries == [completionRecord])
        #expect(remainingState == nil)
        #expect(viewModel.pendingCompletionRecord == completionRecord)
        #expect(viewModel.hasCompletedCleanup)
        #expect(!viewModel.isDeleting)
    }

    /// The keeper's protection is a selection invariant, so assert it where it
    /// actually matters: the identifiers handed to the cleanup service.
    @Test func testConfirmDeleteNeverSendsTheBestShotToCleanup() async {
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
        #expect(viewModel.bestShotAssetID == "one")
        #expect(!(lastSelection?.contains("one") ?? true))
        #expect(lastSelection == Set(["best"]))
    }

    @Test func testConfirmDeletePublishesCompletionAfterReviewStateRemovalFinishes() async {
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

        #expect(viewModel.pendingCompletionRecord == nil)
        #expect(viewModel.isDeleting)
        let storedEntries = await cleanupHistoryRepository.entries
        #expect(storedEntries == [completionRecord])

        await suspendedRepository.finishDelete()
        await deleteTask.value

        #expect(viewModel.pendingCompletionRecord == completionRecord)
        #expect(!viewModel.isDeleting)
    }

    @Test func testConfirmDeleteWaitsForCompletionDelayBeforePublishing() async throws {
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
        #expect(remainingState == nil)
        #expect(viewModel.pendingCompletionRecord == nil)
        #expect(viewModel.isDeleting)

        await completionDelay.finish()
        await deleteTask.value

        #expect(viewModel.pendingCompletionRecord == completionRecord)
        #expect(!viewModel.isDeleting)
    }

    @Test func testConfirmDeleteFailurePreservesSelectionAndShowsMessage() async {
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

        #expect(viewModel.selectedAssetIDs == ["one"])
        #expect(viewModel.pendingCompletionRecord == nil)
        #expect(viewModel.actionErrorMessage == DetailsL10n.Common.couldntMoveSelectedPhotosPlease)
        #expect(viewModel.currentAlikeReaction?.state == .recoverableError(AlikeErrorContext(operation: .cleanup)))
        #expect(!viewModel.isDeleting)

        viewModel.clearActionError()

        #expect(viewModel.currentAlikeReaction?.state == .cleanupReady(AlikeCleanupSummary(itemCount: 1, estimatedSavingsBytes: 45)))
    }

    @Test func testConfirmDeleteDoesNotRunWithoutSelection() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()
        await viewModel.confirmDelete()

        let cleanupDidRun = await cleanupService.didCallDeleteAssets
        #expect(!cleanupDidRun)
        #expect(viewModel.actionErrorMessage == DetailsL10n.Common.selectAtLeastOnePhoto)
    }

    @Test func testDismissingDeleteErrorClearsErrorState() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "candidate", isFavorite: false, area: 90, createdAt: nil)
            ]
        )

        await viewModel.load()
        await viewModel.confirmDelete()

        #expect(viewModel.isActionErrorPresented)

        viewModel.isActionErrorPresented = false

        #expect(!viewModel.isActionErrorPresented)
        #expect(viewModel.actionErrorMessage == nil)
        #expect(!viewModel.shouldOfferOpenSettings)
    }

    @Test func testDeleteConfirmationCopyReflectsSelectionCountAndSavings() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 300, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 200, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 100, createdAt: nil)
            ]
        )

        await viewModel.load()
        viewModel.toggleSelection(for: "one")

        #expect(viewModel.deleteConfirmationTitle == DetailsL10n.ClusterDetails.deleteAlertTitle(1))
        #expect(viewModel.deleteConfirmationMessage == String(
                format: DetailsL10n.ClusterDetails.selectedPhotoWillBeRemoved,
                viewModel.estimatedSavingsText
            ))

        viewModel.toggleSelection(for: "two")

        #expect(viewModel.deleteConfirmationTitle == DetailsL10n.ClusterDetails.deleteAlertTitle(2))
        #expect(viewModel.deleteConfirmationMessage == String(
                format: DetailsL10n.ClusterDetails.selectedPhotosWillBeRemoved,
                viewModel.estimatedSavingsText
            ))
    }

    @Test func testFreeUserCanRequestSinglePhotoCleanup() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ]
        )
        await viewModel.load()
        viewModel.selectAllExceptBest()

        let decision = viewModel.requestDeleteConfirmation()

        #expect(decision == .allowed)
        #expect(viewModel.isDeleteConfirmationPresented)
    }

    @Test func testFreeUserCannotRequestOrConfirmMultiPhotoCleanup() async {
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

        #expect(decision == .requiresPremium)
        #expect(!viewModel.isDeleteConfirmationPresented)
        #expect(viewModel.selectedAssetIDs == ["one", "two"])
        #expect(!cleanupDidRun)
    }

    @Test func testContinueFreeKeepsFirstSelectedAssetInVisibleOrder() async {
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil),
                snapshot(id: "two", isFavorite: false, area: 80, createdAt: nil)
            ]
        )
        await viewModel.load()
        viewModel.selectAllExceptBest()

        #expect(viewModel.requiresPremiumForCurrentSelection)
        await viewModel.continueWithSingleFreeSelection()

        #expect(viewModel.selectedAssetIDs == ["one"])
        #expect(!viewModel.requiresPremiumForCurrentSelection)
        #expect(viewModel.isDeleteConfirmationPresented)
    }

    @Test func testPersistedRevisionAdvancesOnlyAfterEachSaveLands() async {
        let reviewRepository = SuspendableSaveClusterReviewStateRepository()
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "best", isFavorite: true, area: 100, createdAt: nil),
                snapshot(id: "one", isFavorite: false, area: 90, createdAt: nil)
            ],
            reviewRepository: reviewRepository
        )
        await viewModel.load()

        #expect(viewModel.persistedRevision == 0)

        await reviewRepository.suspendNextSave()
        viewModel.toggleSelection(for: "one")
        await reviewRepository.waitUntilSuspendedSaveStarts()

        #expect(viewModel.persistedRevision == 0)

        await reviewRepository.finishSuspendedSave()
        await waitForPersistedRevision(1, on: viewModel)

        viewModel.toggleSelection(for: "one")
        await waitForPersistedRevision(2, on: viewModel)
    }

    @Test func testAwaitPendingPersistenceDoesNotReturnUntilTheInFlightSaveLands() async {
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
        #expect(viewModel.persistedRevision == 0)

        let waiter = Task { await viewModel.awaitPendingPersistence() }
        await reviewRepository.finishSuspendedSave()
        await waiter.value

        // The host reads the repository as soon as this returns, so the write
        // has to be on disk by now, not merely enqueued.
        #expect(viewModel.persistedRevision == 1)
        let persisted = try? await reviewRepository.loadReviewState(clusterID: clusterID)
        #expect(persisted?.selectedLocalIdentifiers == ["one"])
    }

    @Test func testContinueFreeSerializesEarlierSaveBeforeConfirmationAndDeletion() async {
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

        #expect(!viewModel.isDeleteConfirmationPresented)

        await reviewRepository.finishSuspendedSave()
        await continueTask.value

        #expect(viewModel.isDeleteConfirmationPresented)
        let persistedFallbackState = await reviewRepository.storedState(clusterID: clusterID)
        #expect(persistedFallbackState?.selectedLocalIdentifiers == ["one"])

        await viewModel.confirmDelete()

        let stateAfterDelete = await reviewRepository.storedState(clusterID: clusterID)
        #expect(stateAfterDelete == nil)
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
        #expect(viewModel.persistedRevision == expected, sourceLocation: sourceLocation)
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
