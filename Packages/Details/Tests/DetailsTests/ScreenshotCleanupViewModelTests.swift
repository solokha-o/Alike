import Foundation
import Testing
import Core
@testable import Details

@MainActor
@Suite struct ScreenshotCleanupViewModelTests {
    private let cleanupService = MockPhotoCleanupService()
    private let cleanupHistoryRepository = MockCleanupHistoryRepository()

    @Test func testSelectionUpdatesEstimatedSavings() {
        let viewModel = makeViewModel()

        viewModel.toggleSelection(for: "one")

        #expect(viewModel.selectedAssetIDs == ["one"])
        #expect(viewModel.estimatedSavingsBytes == 100)
    }

    @Test func testMaximumEstimatedSavingsIncludesEveryAsset() {
        let viewModel = makeViewModel()

        #expect(viewModel.maximumEstimatedSavingsBytes == 150)
    }

    @Test func testSelectAllAndClearSelection() {
        let viewModel = makeViewModel()

        viewModel.selectAll()
        #expect(viewModel.selectedAssetIDs == ["one", "two"])
        #expect(viewModel.estimatedSavingsBytes == 150)

        viewModel.clearSelection()
        #expect(viewModel.selectedAssetIDs.isEmpty)
        #expect(viewModel.estimatedSavingsBytes == 0)
    }

    @Test func testFreeUserCanDeleteSinglePhoto() async throws {
        let expectedRecord = CleanupCompletionRecord(
            sourceClusterID: CleanupCategoryKind.screenshots.sourceClusterID,
            deletedCount: 1,
            estimatedSavingsBytes: 100
        )
        await cleanupService.setDeleteAssetsResult(.success(expectedRecord))
        let viewModel = makeViewModel()
        viewModel.toggleSelection(for: "one")

        let decision = viewModel.requestDeleteConfirmation()
        await viewModel.confirmDelete()

        let lastIdentifiers = await cleanupService.lastLocalIdentifiers
        #expect(decision == .allowed)
        #expect(lastIdentifiers == ["one"])
        #expect(viewModel.pendingCompletionRecord == expectedRecord)
    }

    @Test func testFreeUserCannotRequestOrConfirmMultiPhotoCleanup() async {
        let viewModel = makeViewModel()
        viewModel.selectAll()

        let decision = viewModel.requestDeleteConfirmation()
        await viewModel.confirmDelete()
        let cleanupDidRun = await cleanupService.didCallDeleteAssets

        #expect(decision == .requiresPremium)
        #expect(!viewModel.isDeleteConfirmationPresented)
        #expect(viewModel.selectedAssetIDs == ["one", "two"])
        #expect(!cleanupDidRun)
    }

    @Test func testContinueFreeKeepsFirstSelectedAssetInVisibleOrder() {
        let viewModel = makeViewModel()
        viewModel.selectAll()

        #expect(viewModel.requiresPremiumForCurrentSelection)
        viewModel.continueWithSingleFreeSelection()

        #expect(viewModel.selectedAssetIDs == ["one"])
        #expect(!viewModel.requiresPremiumForCurrentSelection)
        #expect(viewModel.isDeleteConfirmationPresented)
    }

    @Test func testPremiumUserCanDeleteMultiplePhotos() async throws {
        let expectedRecord = CleanupCompletionRecord(
            sourceClusterID: CleanupCategoryKind.screenshots.sourceClusterID,
            deletedCount: 2,
            estimatedSavingsBytes: 150
        )
        await cleanupService.setDeleteAssetsResult(.success(expectedRecord))
        let viewModel = makeViewModel(
            premiumAccess: MockPremiumAccessController(unlockedFeatures: [.batchCleanup])
        )
        viewModel.selectAll()

        await viewModel.confirmDelete()

        let lastIdentifiers = await cleanupService.lastLocalIdentifiers
        let lastSource = await cleanupService.lastSourceClusterID
        let lastEstimatedSavings = await cleanupService.lastEstimatedSavingsBytes

        #expect(lastIdentifiers == ["one", "two"])
        #expect(lastSource == CleanupCategoryKind.screenshots.sourceClusterID)
        #expect(lastEstimatedSavings == 150)
        #expect(viewModel.pendingCompletionRecord == expectedRecord)
    }

    @Test func testConfirmDeletePublishesCompletionAfterHistoryAppendFinishes() async {
        let expectedRecord = CleanupCompletionRecord(
            sourceClusterID: CleanupCategoryKind.screenshots.sourceClusterID,
            deletedCount: 2,
            estimatedSavingsBytes: 150
        )
        let suspendedHistoryRepository = SuspendedScreenshotCleanupHistoryRepository()
        await cleanupService.setDeleteAssetsResult(.success(expectedRecord))
        let viewModel = makeViewModel(
            cleanupHistoryRepository: suspendedHistoryRepository,
            premiumAccess: MockPremiumAccessController(unlockedFeatures: [.batchCleanup])
        )
        viewModel.selectAll()

        let deleteTask = Task { await viewModel.confirmDelete() }
        await suspendedHistoryRepository.waitUntilAppendStarts()

        #expect(viewModel.pendingCompletionRecord == nil)
        #expect(viewModel.isDeleting)

        await suspendedHistoryRepository.finishAppend()
        await deleteTask.value

        #expect(viewModel.pendingCompletionRecord == expectedRecord)
        #expect(!viewModel.isDeleting)
        let entries = await suspendedHistoryRepository.storedEntries()
        #expect(entries == [expectedRecord])
    }

    @Test func testBlurredPhotoCompletionWaitsForDelayBeforePublishing() async {
        let expectedRecord = CleanupCompletionRecord(
            sourceClusterID: CleanupCategoryKind.blurredPhotos.sourceClusterID,
            deletedCount: 2,
            estimatedSavingsBytes: 150
        )
        let suspendedDelay = SuspendedScreenshotCleanupCompletionDelay()
        await cleanupService.setDeleteAssetsResult(.success(expectedRecord))
        let viewModel = makeViewModel(
            sourceCategory: .blurredPhotos,
            premiumAccess: MockPremiumAccessController(unlockedFeatures: [.batchCleanup]),
            completionDelay: { await suspendedDelay.wait() }
        )
        viewModel.selectAll()

        let deleteTask = Task { await viewModel.confirmDelete() }
        await suspendedDelay.waitUntilStarted()

        let lastSource = await cleanupService.lastSourceClusterID
        #expect(lastSource == CleanupCategoryKind.blurredPhotos.sourceClusterID)
        #expect(viewModel.pendingCompletionRecord == nil)
        #expect(viewModel.isDeleting)

        await suspendedDelay.finish()
        await deleteTask.value

        #expect(viewModel.pendingCompletionRecord == expectedRecord)
        #expect(!viewModel.isDeleting)
    }

    private func makeViewModel(
        sourceCategory: CleanupCategoryKind = .screenshots,
        cleanupHistoryRepository: (any CleanupHistoryRepository)? = nil,
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        completionDelay: @escaping @MainActor @Sendable () async -> Void = {}
    ) -> ScreenshotCleanupViewModel {
        ScreenshotCleanupViewModel(
            assets: [],
            sourceCategory: sourceCategory,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository ?? self.cleanupHistoryRepository,
            premiumAccess: premiumAccess,
            assetSnapshots: [
                snapshot(id: "one", area: 200),
                snapshot(id: "two", area: 100)
            ],
            completionDelay: completionDelay
        )
    }

    private func snapshot(id: String, area: Int) -> ReviewAssetSnapshot {
        ReviewAssetSnapshot(
            localIdentifier: id,
            isFavorite: false,
            pixelWidth: area,
            pixelHeight: 1,
            creationDate: nil
        )
    }
}

private actor SuspendedScreenshotCleanupCompletionDelay {
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

private actor SuspendedScreenshotCleanupHistoryRepository: CleanupHistoryRepository {
    private var entries: [CleanupCompletionRecord] = []
    private var appendContinuation: CheckedContinuation<Void, Never>?
    private var appendStarted = false

    func loadEntries() async throws -> [CleanupCompletionRecord] {
        entries
    }

    func append(_ entry: CleanupCompletionRecord) async throws {
        appendStarted = true
        await withCheckedContinuation { continuation in
            appendContinuation = continuation
        }
        entries.append(entry)
    }

    func waitUntilAppendStarts() async {
        while !appendStarted {
            await Task.yield()
        }
    }

    func finishAppend() {
        appendContinuation?.resume()
        appendContinuation = nil
    }

    func storedEntries() -> [CleanupCompletionRecord] {
        entries
    }
}
