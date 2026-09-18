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
