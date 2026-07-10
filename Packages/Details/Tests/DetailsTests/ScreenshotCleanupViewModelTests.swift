import XCTest
import Core
@testable import Details

@MainActor
final class ScreenshotCleanupViewModelTests: XCTestCase {
    private var cleanupService: MockPhotoCleanupService!
    private var cleanupHistoryRepository: MockCleanupHistoryRepository!

    override func setUp() async throws {
        cleanupService = MockPhotoCleanupService()
        cleanupHistoryRepository = MockCleanupHistoryRepository()
    }

    override func tearDown() async throws {
        cleanupService = nil
        cleanupHistoryRepository = nil
    }

    func testSelectionUpdatesEstimatedSavings() {
        let viewModel = makeViewModel()

        viewModel.toggleSelection(for: "one")

        XCTAssertEqual(viewModel.selectedAssetIDs, ["one"])
        XCTAssertEqual(viewModel.estimatedSavingsBytes, 100)
    }

    func testSelectAllAndClearSelection() {
        let viewModel = makeViewModel()

        viewModel.selectAll()
        XCTAssertEqual(viewModel.selectedAssetIDs, ["one", "two"])
        XCTAssertEqual(viewModel.estimatedSavingsBytes, 150)

        viewModel.clearSelection()
        XCTAssertTrue(viewModel.selectedAssetIDs.isEmpty)
        XCTAssertEqual(viewModel.estimatedSavingsBytes, 0)
    }

    func testConfirmDeletePassesSelectedAssetsAndCategorySourceID() async throws {
        let expectedRecord = CleanupCompletionRecord(
            sourceClusterID: CleanupCategoryKind.screenshots.sourceClusterID,
            deletedCount: 2,
            estimatedSavingsBytes: 150
        )
        await cleanupService.setDeleteAssetsResult(.success(expectedRecord))
        let viewModel = makeViewModel()
        viewModel.selectAll()

        await viewModel.confirmDelete()

        let lastIdentifiers = await cleanupService.lastLocalIdentifiers
        let lastSource = await cleanupService.lastSourceClusterID
        let lastEstimatedSavings = await cleanupService.lastEstimatedSavingsBytes

        XCTAssertEqual(lastIdentifiers, ["one", "two"])
        XCTAssertEqual(lastSource, CleanupCategoryKind.screenshots.sourceClusterID)
        XCTAssertEqual(lastEstimatedSavings, 150)
        XCTAssertEqual(viewModel.pendingCompletionRecord, expectedRecord)
    }

    func testConfirmDeletePublishesCompletionAfterHistoryAppendFinishes() async {
        let expectedRecord = CleanupCompletionRecord(
            sourceClusterID: CleanupCategoryKind.screenshots.sourceClusterID,
            deletedCount: 2,
            estimatedSavingsBytes: 150
        )
        let suspendedHistoryRepository = SuspendedScreenshotCleanupHistoryRepository()
        await cleanupService.setDeleteAssetsResult(.success(expectedRecord))
        let viewModel = makeViewModel(cleanupHistoryRepository: suspendedHistoryRepository)
        viewModel.selectAll()

        let deleteTask = Task { await viewModel.confirmDelete() }
        await suspendedHistoryRepository.waitUntilAppendStarts()

        XCTAssertNil(viewModel.pendingCompletionRecord)
        XCTAssertTrue(viewModel.isDeleting)

        await suspendedHistoryRepository.finishAppend()
        await deleteTask.value

        XCTAssertEqual(viewModel.pendingCompletionRecord, expectedRecord)
        XCTAssertFalse(viewModel.isDeleting)
        let entries = await suspendedHistoryRepository.storedEntries()
        XCTAssertEqual(entries, [expectedRecord])
    }

    private func makeViewModel(
        cleanupHistoryRepository: (any CleanupHistoryRepository)? = nil
    ) -> ScreenshotCleanupViewModel {
        ScreenshotCleanupViewModel(
            assets: [],
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository ?? self.cleanupHistoryRepository,
            assetSnapshots: [
                snapshot(id: "one", area: 200),
                snapshot(id: "two", area: 100)
            ]
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
