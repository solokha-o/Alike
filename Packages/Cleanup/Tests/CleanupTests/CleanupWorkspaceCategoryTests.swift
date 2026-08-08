import Cleanup
import Core
import Photos
import XCTest

/// Covers what the workspace does with smart-category and history data around a
/// cached load: the order it presents categories in, what a missing category
/// means, and that a repository failure degrades to an empty section instead of
/// taking the whole workspace down.
@MainActor
final class CleanupWorkspaceCategoryTests: XCTestCase {
    func testEachCategoryCarriesItsOwnSnapshotNumbersInKindOrder() async {
        let categoryRepository = MockCleanupCategorySnapshotRepository()
        await categoryRepository.setStoredSnapshots([
            .blurredPhotos: snapshot(kind: .blurredPhotos, assetCount: 4, bytes: 400),
            .screenshots: snapshot(kind: .screenshots, assetCount: 7, bytes: 700)
        ])
        let workspace = await makeScannedWorkspace(categoryRepository: categoryRepository)

        await workspace.loadCachedContent()

        // `loadAllSnapshots` returns a Dictionary, so the repository imposes no
        // order at all — `CleanupCategoryKind.allCases` is the only thing that
        // can give the Cleanup tab a stable one. With two kinds this assertion
        // only catches a regression about half the time (Swift seeds Dictionary
        // ordering per process), but it never fails on correct code, so it is
        // worth keeping. The per-kind values below are what make the test
        // deterministic: they catch a summary attached to the wrong kind.
        XCTAssertEqual(
            workspace.cleanupCategories.map(\.kind),
            CleanupCategoryKind.allCases
        )
        let byKind = Dictionary(
            uniqueKeysWithValues: workspace.cleanupCategories.map { ($0.kind, $0) }
        )
        XCTAssertEqual(byKind[.screenshots]?.assetCount, 7)
        XCTAssertEqual(byKind[.screenshots]?.estimatedSavingsBytes, 700)
        XCTAssertEqual(byKind[.blurredPhotos]?.assetCount, 4)
        XCTAssertEqual(byKind[.blurredPhotos]?.estimatedSavingsBytes, 400)
    }

    func testCategoryMissingFromRepositoryIsDroppedRatherThanShownEmpty() async {
        let categoryRepository = MockCleanupCategorySnapshotRepository()
        await categoryRepository.setStoredSnapshots([
            .screenshots: snapshot(kind: .screenshots, assetCount: 2, bytes: 200)
        ])
        let workspace = await makeScannedWorkspace(categoryRepository: categoryRepository)

        await workspace.loadCachedContent()

        XCTAssertEqual(workspace.cleanupCategories.map(\.kind), [.screenshots])
    }

    func testCategoryRepositoryFailureLeavesCategoriesEmptyWithoutFailingTheLoad() async {
        let categoryRepository = MockCleanupCategorySnapshotRepository()
        await categoryRepository.setStoredSnapshots([
            .screenshots: snapshot(kind: .screenshots, assetCount: 2, bytes: 200)
        ])
        await categoryRepository.setLoadAllSnapshotsError(CategoryReadFailure())
        let workspace = await makeScannedWorkspace(categoryRepository: categoryRepository)

        await workspace.loadCachedContent()

        XCTAssertEqual(workspace.cleanupCategories, [])
        // The rest of the workspace still has to arrive: a category read is one
        // section of the Cleanup tab, not a precondition for it.
        XCTAssertNotNil(workspace.content)
        XCTAssertEqual(workspace.contentState, .content(workspace.content!))
    }

    func testHistoryRepositoryFailureYieldsEmptyInsightsWithoutFailingTheLoad() async {
        let historyRepository = MockCleanupHistoryRepository(entries: [
            CleanupCompletionRecord(
                sourceClusterID: UUID(),
                deletedCount: 3,
                estimatedSavingsBytes: 3_072,
                completedAt: Date(timeIntervalSince1970: 1_000)
            )
        ])
        await historyRepository.setLoadEntriesError(HistoryReadFailure())
        let workspace = await makeScannedWorkspace(historyRepository: historyRepository)

        await workspace.loadCachedContent()

        XCTAssertEqual(workspace.cleanupInsights, .empty)
        XCTAssertFalse(workspace.cleanupInsights.hasHistory)
        XCTAssertNotNil(workspace.content)
    }

    func testFailedScanRestoresThePreScanCategorySnapshots() async {
        let categoryRepository = MockCleanupCategorySnapshotRepository()
        let preScan = snapshot(kind: .screenshots, assetCount: 9, bytes: 900)
        await categoryRepository.setStoredSnapshots([.screenshots: preScan])
        // The real analysis service rewrites the category snapshots as part of
        // refreshing them, and that happens *before* clusters are persisted. So
        // the double has to write too, or the restore has nothing to undo and
        // the test would pass against a workspace that never restores anything.
        let analysis = CategoryWritingAnalysisService(
            repository: categoryRepository,
            refreshed: snapshot(kind: .blurredPhotos, assetCount: 1, bytes: 100)
        )
        let workspace = makeWorkspace(
            analysisService: analysis,
            repository: FailingSaveClusterRepository(),
            categoryRepository: categoryRepository
        )

        do {
            _ = try await workspace.scan(sensitivity: .medium)
            XCTFail("Expected the scan to fail while persisting clusters")
        } catch {
            // Expected: the save is what fails, after analysis succeeded.
        }

        let restored = await categoryRepository.storedSnapshots
        XCTAssertEqual(restored, [.screenshots: preScan])
    }

    // MARK: - Helpers

    private func snapshot(
        kind: CleanupCategoryKind,
        assetCount: Int,
        bytes: Int64
    ) -> CleanupCategorySnapshot {
        CleanupCategorySnapshot(
            kind: kind,
            localIdentifiers: (0..<assetCount).map { "\(kind.rawValue)-\($0)" },
            assetCount: assetCount,
            estimatedSavingsBytes: bytes,
            refreshedAt: Date(timeIntervalSince1970: 10)
        )
    }

    /// A workspace whose repository already reports a completed scan, so
    /// `loadCachedContent` publishes content instead of `.neverScanned`.
    private func makeScannedWorkspace(
        categoryRepository: MockCleanupCategorySnapshotRepository = MockCleanupCategorySnapshotRepository(),
        historyRepository: MockCleanupHistoryRepository = MockCleanupHistoryRepository()
    ) async -> CleanupWorkspaceModel {
        let repository = MockPhotoClusterRepository()
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        return makeWorkspace(
            repository: repository,
            categoryRepository: categoryRepository,
            historyRepository: historyRepository
        )
    }

    private func makeWorkspace(
        analysisService: any PhotoAnalysisService = MockPhotoAnalysisService(),
        repository: any PhotoClusterRepository = MockPhotoClusterRepository(),
        categoryRepository: any CleanupCategorySnapshotRepository = MockCleanupCategorySnapshotRepository(),
        historyRepository: any CleanupHistoryRepository = MockCleanupHistoryRepository()
    ) -> CleanupWorkspaceModel {
        CleanupWorkspaceModel(
            analysisService: analysisService,
            repository: repository,
            reviewRepository: MockClusterReviewStateRepository(),
            cleanupCategoryRepository: categoryRepository,
            cleanupSessionRepository: MockCleanupSessionRepository(),
            cleanupHistoryRepository: historyRepository
        )
    }
}

private struct CategoryReadFailure: LocalizedError {
    var errorDescription: String? { "Category read failed" }
}

private struct HistoryReadFailure: LocalizedError {
    var errorDescription: String? { "History read failed" }
}

/// Analysis succeeds, persistence does not — the path that triggers
/// `restorePersistedContent`.
private actor FailingSaveClusterRepository: PhotoClusterRepository {
    private let delegate = MockPhotoClusterRepository()

    func loadClusters() async throws -> [PhotoCluster] {
        try await delegate.loadClusters()
    }

    func saveClusters(_ clusters: [PhotoCluster]) async throws {
        throw ClusterSaveFailure()
    }

    func loadClusterSnapshots() async throws -> [PhotoClusterSnapshot] {
        try await delegate.loadClusterSnapshots()
    }

    func deleteAllClusters() async throws {
        try await delegate.deleteAllClusters()
    }

    func getLastScanDate() async -> Date? {
        await delegate.getLastScanDate()
    }

    func updateLastScanDate(_ date: Date) async throws {
        try await delegate.updateLastScanDate(date)
    }

    func loadScanMetadata() async -> ScanMetadataSnapshot? {
        await delegate.loadScanMetadata()
    }

    func updateScanMetadata(_ metadata: ScanMetadataSnapshot?) async throws {
        try await delegate.updateScanMetadata(metadata)
    }

    func captureScanMetadata(completedAt: Date) async -> ScanMetadataSnapshot {
        await delegate.captureScanMetadata(completedAt: completedAt)
    }

    func hasGalleryChanged() async -> Bool {
        await delegate.hasGalleryChanged()
    }
}

private struct ClusterSaveFailure: LocalizedError {
    var errorDescription: String? { "Cluster save failed" }
}

/// Mirrors the real analysis service: refreshing categories replaces what is in
/// the category repository.
private actor CategoryWritingAnalysisService: PhotoAnalysisService {
    private let delegate = MockPhotoAnalysisService()
    private let repository: any CleanupCategorySnapshotRepository
    private let refreshed: CleanupCategorySnapshot

    init(
        repository: any CleanupCategorySnapshotRepository,
        refreshed: CleanupCategorySnapshot
    ) {
        self.repository = repository
        self.refreshed = refreshed
    }

    func analyzePhotoLibrary(
        sensitivity: Float,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [PhotoCluster] {
        [PhotoCluster(id: UUID(), assets: [])]
    }

    func refreshCleanupCategories(
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [CleanupCategorySummary] {
        try await repository.replaceAllSnapshots([refreshed])
        return [refreshed.summary]
    }

    func summarizeCleanupCategories() async throws -> [CleanupCategorySummary] {
        try await delegate.summarizeCleanupCategories()
    }

    func loadAssets(for category: CleanupCategoryKind) async throws -> [PHAsset] {
        try await delegate.loadAssets(for: category)
    }

    func calculateSimilarity(asset1: PHAsset, asset2: PHAsset) async throws -> Float {
        try await delegate.calculateSimilarity(asset1: asset1, asset2: asset2)
    }
}
