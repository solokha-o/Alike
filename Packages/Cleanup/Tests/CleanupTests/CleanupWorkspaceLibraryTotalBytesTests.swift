import Core
import XCTest
@testable import Cleanup

/// The widget ring's denominator: unknown until a scan summed the library, then
/// the scan's figure, across cold launches, until local data is deleted.
@MainActor
final class CleanupWorkspaceLibraryTotalBytesTests: XCTestCase {
    func testIsNilBeforeTheFirstScan() async {
        let byteSizes = MockAssetByteSizeRepository()
        // A leftover total without a scan baseline must not surface.
        await byteSizes.setStoredLibraryTotalBytes(6_400_000_000)
        let workspace = makeWorkspace(byteSizeRepository: byteSizes)

        await workspace.loadCachedContent()

        XCTAssertNil(workspace.libraryTotalBytes)
    }

    func testScanAdoptsAndPersistsTheAnalysisTotal() async throws {
        let analysis = MockPhotoAnalysisService()
        await analysis.setLibraryTotalBytesResult(6_400_000_000)
        let byteSizes = MockAssetByteSizeRepository()
        let workspace = makeWorkspace(analysisService: analysis, byteSizeRepository: byteSizes)

        _ = try await workspace.scan(sensitivity: .medium)

        XCTAssertEqual(workspace.libraryTotalBytes, 6_400_000_000)
        let stored = await byteSizes.storedLibraryTotalBytes
        XCTAssertEqual(stored, 6_400_000_000)
    }

    func testColdLaunchRestoresThePersistedTotal() async throws {
        let analysis = MockPhotoAnalysisService()
        await analysis.setLibraryTotalBytesResult(6_400_000_000)
        let repository = MockPhotoClusterRepository()
        let byteSizes = MockAssetByteSizeRepository()
        _ = try await makeWorkspace(
            analysisService: analysis,
            repository: repository,
            byteSizeRepository: byteSizes
        ).scan(sensitivity: .medium)

        let relaunched = makeWorkspace(repository: repository, byteSizeRepository: byteSizes)
        await relaunched.loadCachedContent()

        XCTAssertEqual(relaunched.libraryTotalBytes, 6_400_000_000)
    }

    func testScanWithoutAMeasurementKeepsThePreviousTotal() async throws {
        let analysis = MockPhotoAnalysisService()
        await analysis.setLibraryTotalBytesResult(6_400_000_000)
        let byteSizes = MockAssetByteSizeRepository()
        let workspace = makeWorkspace(analysisService: analysis, byteSizeRepository: byteSizes)
        _ = try await workspace.scan(sensitivity: .medium)

        await analysis.setLibraryTotalBytesResult(nil)
        _ = try await workspace.scan(sensitivity: .medium)

        XCTAssertEqual(workspace.libraryTotalBytes, 6_400_000_000)
        let saves = await byteSizes.saveLibraryTotalBytesCallCount
        XCTAssertEqual(saves, 1)
    }

    func testDataDeletionClearsTheTotal() async throws {
        let analysis = MockPhotoAnalysisService()
        await analysis.setLibraryTotalBytesResult(6_400_000_000)
        let byteSizes = MockAssetByteSizeRepository()
        let workspace = makeWorkspace(analysisService: analysis, byteSizeRepository: byteSizes)
        _ = try await workspace.scan(sensitivity: .medium)

        await workspace.prepareForDataDeletion()

        XCTAssertNil(workspace.libraryTotalBytes)
        let stored = await byteSizes.storedLibraryTotalBytes
        XCTAssertNil(stored)
    }

    func testStaleCachedLoadDoesNotOverwriteANewerScanTotal() async throws {
        let analysis = MockPhotoAnalysisService()
        await analysis.setLibraryTotalBytesResult(100)
        let repository = MockPhotoClusterRepository()
        let byteSizes = GatedLibraryTotalRepository()
        _ = try await makeWorkspace(
            analysisService: analysis,
            repository: repository,
            byteSizeRepository: byteSizes
        ).scan(sensitivity: .medium)

        // A relaunch: the cached load parks on the total it already read as 100.
        let workspace = makeWorkspace(
            analysisService: analysis,
            repository: repository,
            byteSizeRepository: byteSizes
        )
        await byteSizes.gateNextLoad()
        let staleLoad = Task { @MainActor in await workspace.loadCachedContent() }
        await byteSizes.waitUntilLoadSuspends()
        await analysis.setLibraryTotalBytesResult(200)
        _ = try await workspace.scan(sensitivity: .medium)
        await byteSizes.releaseLoad()
        await staleLoad.value

        XCTAssertEqual(workspace.libraryTotalBytes, 200)
    }

    func testUnchangedTotalIsSavedAgainAfterAFailedWrite() async throws {
        let analysis = MockPhotoAnalysisService()
        await analysis.setLibraryTotalBytesResult(100)
        let byteSizes = FailOnceLibraryTotalRepository()
        let workspace = makeWorkspace(analysisService: analysis, byteSizeRepository: byteSizes)

        _ = try await workspace.scan(sensitivity: .medium)
        _ = try await workspace.scan(sensitivity: .medium)

        let stored = await byteSizes.storedLibraryTotalBytes
        XCTAssertEqual(stored, 100)
    }

    private func makeWorkspace(
        analysisService: any PhotoAnalysisService = MockPhotoAnalysisService(),
        repository: any PhotoClusterRepository = MockPhotoClusterRepository(),
        byteSizeRepository: any AssetByteSizeRepository
    ) -> CleanupWorkspaceModel {
        CleanupWorkspaceModel(
            analysisService: analysisService,
            repository: repository,
            reviewRepository: MockClusterReviewStateRepository(),
            cleanupCategoryRepository: MockCleanupCategorySnapshotRepository(),
            cleanupSessionRepository: MockCleanupSessionRepository(),
            cleanupHistoryRepository: MockCleanupHistoryRepository(),
            assetByteSizeRepository: byteSizeRepository
        )
    }
}

/// Suspends one `loadLibraryTotalBytes()` after it captured the stored value, so
/// a scan can finish while the cached load is parked on exactly that read.
private actor GatedLibraryTotalRepository: AssetByteSizeRepository {
    private var storedLibraryTotalBytes: Int64?
    private var isGated = false
    private var isSuspended = false
    private var suspensionWaiter: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func loadAll() async -> [AssetByteSizeRecord] { [] }
    func replaceAll(_ records: [AssetByteSizeRecord]) async throws {}

    func gateNextLoad() { isGated = true }

    func waitUntilLoadSuspends() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { suspensionWaiter = $0 }
    }

    func releaseLoad() {
        release?.resume()
        release = nil
    }

    func loadLibraryTotalBytes() async -> Int64? {
        let captured = storedLibraryTotalBytes
        guard isGated else { return captured }
        isGated = false
        await withCheckedContinuation { continuation in
            release = continuation
            isSuspended = true
            suspensionWaiter?.resume()
            suspensionWaiter = nil
        }
        return captured
    }

    func saveLibraryTotalBytes(_ bytes: Int64?) async throws {
        storedLibraryTotalBytes = bytes
    }
}

private actor FailOnceLibraryTotalRepository: AssetByteSizeRepository {
    private(set) var storedLibraryTotalBytes: Int64?
    private var hasFailed = false

    func loadAll() async -> [AssetByteSizeRecord] { [] }
    func replaceAll(_ records: [AssetByteSizeRecord]) async throws {}

    func loadLibraryTotalBytes() async -> Int64? { storedLibraryTotalBytes }

    func saveLibraryTotalBytes(_ bytes: Int64?) async throws {
        guard hasFailed else {
            hasFailed = true
            throw CocoaError(.fileWriteUnknown)
        }
        storedLibraryTotalBytes = bytes
    }
}
