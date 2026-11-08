import CleanupWorkspace
import Core
import Observation
import Photos
import Foundation
import Testing

private enum ScanPersistenceTestError: Error {
    case failed
}

@MainActor
struct CleanupWorkspaceModelTests {
    @Test func testCachedContentWithoutBaselineIsNeverScanned() async {
        let workspace = makeWorkspace()

        await workspace.loadCachedContent()

        #expect(workspace.contentState == .neverScanned)
        #expect(workspace.content == nil)
    }

    @Test func testSuccessfulScanPublishesSummaryAndCompletedEmptyContent() async throws {
        let analysis = MockPhotoAnalysisService()
        let workspace = makeWorkspace(analysisService: analysis)

        let summary = try await workspace.scan(sensitivity: .medium)

        #expect(summary.clusterCount == 0)
        #expect(summary.cleanupCategoryCandidateCount == 0)
        #expect(workspace.lastScanSummary == summary)
        #expect(workspace.lastCompletedScanDate == summary.completedAt)
        #expect(workspace.content?.clusters == [])
        #expect(workspace.scanOperation == .idle)
    }

    @Test func testCompletedScanDoesNotImmediatelyAskForARescan() async throws {
        let repository = MockPhotoClusterRepository()
        let workspace = makeWorkspace(
            analysisService: MockPhotoAnalysisService(),
            repository: repository
        )

        _ = try await workspace.scan(sensitivity: .medium)
        let shouldPrompt = await workspace.checkForGalleryChanges()

        #expect(!shouldPrompt)
        #expect(!workspace.shouldShowRescanPrompt)
    }

    @Test func testScanRecordsLibraryFingerprintOnceAfterClustersArePersisted() async throws {
        let repository = MockPhotoClusterRepository()
        await repository.setLibraryFingerprint(token: Data([0xCD]), imageAssetCount: 12)
        let workspace = makeWorkspace(
            analysisService: MockPhotoAnalysisService(),
            repository: repository
        )

        let summary = try await workspace.scan(sensitivity: .medium)

        let log = await repository.persistenceLog
        #expect(log == ["saveClusters", "updateScanMetadata"])

        let writes = await repository.scanMetadataWrites
        #expect(writes.count == 1)
        #expect((writes.first??.libraryChangeToken) == Data([0xCD]))
        #expect((writes.first??.imageAssetCount) == 12)
        #expect((writes.first??.lastScanDate) == summary.completedAt)
    }

    /// Guards against a regression where the fingerprint was captured only
    /// after clusters were persisted: a photo added or removed while
    /// Vision/category work is still running would then be folded into the
    /// recorded baseline while remaining absent from the clusters that work
    /// actually produced, so the next change check would see no delta and
    /// never prompt for the rescan that photo requires.
    @Test func testScanCapturesFingerprintBeforeAnalysisSnapshotsAssetsNotAfter() async throws {
        let repository = MockPhotoClusterRepository()
        await repository.setLibraryFingerprint(token: Data([0x01]), imageAssetCount: 10)
        let analysis = MidScanFingerprintMutatingAnalysisService(
            repository: repository,
            mutatedToken: Data([0x02]),
            mutatedImageAssetCount: 11
        )
        let workspace = makeWorkspace(analysisService: analysis, repository: repository)

        let summary = try await workspace.scan(sensitivity: .medium)

        let writes = await repository.scanMetadataWrites
        #expect(writes.count == 1)
        #expect((writes.first??.libraryChangeToken) == Data([0x01]), "Must persist the fingerprint captured before analysis started, not a value mutated mid-scan")
        #expect((writes.first??.imageAssetCount) == 10)
        #expect((writes.first??.lastScanDate) == summary.completedAt)
    }

    @Test func testFailedScanRestoresThePreviousLibraryFingerprint() async throws {
        let repository = MockPhotoClusterRepository()
        let baseline = ScanMetadataSnapshot(
            lastScanDate: Date(timeIntervalSince1970: 1_700_000_000),
            libraryChangeToken: Data([0xEF]),
            imageAssetCount: 5
        )
        try await repository.updateScanMetadata(baseline)
        await repository.setSaveClustersResult(.failure(ScanPersistenceTestError.failed))
        let workspace = makeWorkspace(
            analysisService: MockPhotoAnalysisService(),
            repository: repository
        )

        do {
            _ = try await workspace.scan(sensitivity: .medium)
            Issue.record("Scan should fail when clusters cannot be persisted")
        } catch {
            // Expected
        }

        let restored = await repository.scanMetadata
        #expect(restored == baseline, "A failed scan must not move the recorded baseline")
    }

    @Test func testCachedContentLoadsPersistedCompletedScanDate() async {
        let repository = MockPhotoClusterRepository()
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        await repository.setGetLastScanDateResult(completedAt)
        let workspace = CleanupWorkspaceModel(
            analysisService: MockPhotoAnalysisService(),
            repository: repository,
            reviewRepository: MockClusterReviewStateRepository(),
            cleanupCategoryRepository: MockCleanupCategorySnapshotRepository(),
            cleanupSessionRepository: MockCleanupSessionRepository(),
            cleanupHistoryRepository: MockCleanupHistoryRepository(),
            bestShotPersonalizedConfigProvider: BestShotPersonalizedScoringConfigProvider(
                repository: MockBestShotPersonalizationRepository()
            ),
            assetByteSizeRepository: MockAssetByteSizeRepository()
        )

        await workspace.loadCachedContent()

        #expect(workspace.lastCompletedScanDate == completedAt)
    }

    @Test func testReviewStatePersistenceFailureDoesNotFailCommittedScan() async throws {
        let workspace = CleanupWorkspaceModel(
            analysisService: MockPhotoAnalysisService(),
            repository: MockPhotoClusterRepository(),
            reviewRepository: FailingReviewStateRepository(),
            cleanupCategoryRepository: MockCleanupCategorySnapshotRepository(),
            cleanupSessionRepository: MockCleanupSessionRepository(),
            cleanupHistoryRepository: MockCleanupHistoryRepository(),
            bestShotPersonalizedConfigProvider: BestShotPersonalizedScoringConfigProvider(
                repository: MockBestShotPersonalizationRepository()
            ),
            assetByteSizeRepository: MockAssetByteSizeRepository()
        )

        let summary = try await workspace.scan(sensitivity: .medium)

        #expect(summary.clusterCount == 0)
        #expect(workspace.scanOperation == .idle)
        #expect(workspace.contentState == .content(try #require(workspace.content)))
    }

    @Test func testUnchangedReviewReloadDoesNotPublishWorkspaceContent() async {
        let cluster = PhotoCluster(id: UUID(), assets: [])
        let repository = MockPhotoClusterRepository()
        await repository.setLoadClustersResult(.success([cluster]))
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        let reviewRepository = MockClusterReviewStateRepository()
        let workspace = makeWorkspace(
            repository: repository,
            reviewRepository: reviewRepository
        )
        await workspace.loadCachedContent()
        let observation = ObservationChangeFlag()

        withObservationTracking {
            _ = workspace.contentState
        } onChange: {
            observation.recordChange()
        }

        await workspace.reloadReviewState()

        #expect(!observation.hasChanged)
    }

    @Test func testChangedReviewReloadPublishesWorkspaceContent() async throws {
        let cluster = PhotoCluster(id: UUID(), assets: [])
        let repository = MockPhotoClusterRepository()
        await repository.setLoadClustersResult(.success([cluster]))
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        let reviewRepository = MockClusterReviewStateRepository()
        let workspace = makeWorkspace(
            repository: repository,
            reviewRepository: reviewRepository
        )
        await workspace.loadCachedContent()
        let updatedState = ClusterReviewState(
            clusterID: cluster.id,
            bestShotLocalIdentifier: "best-shot",
            selectedLocalIdentifiers: ["selected-photo"],
            status: .inReview,
            estimatedSavingsBytes: 128
        )
        await reviewRepository.setStoredStates([cluster.id: updatedState])
        let observation = ObservationChangeFlag()

        withObservationTracking {
            _ = workspace.contentState
        } onChange: {
            observation.recordChange()
        }

        await workspace.reloadReviewState()

        #expect(observation.hasChanged)
        #expect(workspace.reviewStates[cluster.id] == updatedState)
        #expect(workspace.contentState == .content(try #require(workspace.content)))
    }

    /// `sessionProgress()` and `cleanupEntryCluster()` are computed when content
    /// is published rather than on every read, so a review change arriving after
    /// the first read has to be reflected — this is what would go stale if a
    /// publish site ever forgot to refresh the derived snapshots.
    @Test func testDerivedProgressFollowsReviewStateChangesAfterFirstRead() async {
        let cluster = PhotoCluster(id: UUID(), assets: [])
        let repository = MockPhotoClusterRepository()
        await repository.setLoadClustersResult(.success([cluster]))
        await repository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        let reviewRepository = MockClusterReviewStateRepository()
        let workspace = makeWorkspace(
            repository: repository,
            reviewRepository: reviewRepository
        )
        await workspace.loadCachedContent()

        #expect(workspace.sessionProgress().totalClusters == 1)
        #expect(workspace.sessionProgress().reviewedCount == 0)
        #expect(workspace.cleanupEntryCluster()?.id == cluster.id)

        await reviewRepository.setStoredStates([
            cluster.id: ClusterReviewState(
                clusterID: cluster.id,
                bestShotLocalIdentifier: "best-shot",
                selectedLocalIdentifiers: [],
                isReviewConfirmed: true,
                status: .reviewed,
                estimatedSavingsBytes: 128
            ),
        ])
        await workspace.reloadReviewState()

        #expect(workspace.sessionProgress().reviewedCount == 1)
        #expect(workspace.sessionProgress().reviewedSavingsBytes == 128)
        #expect(workspace.cleanupEntryCluster() == nil)
    }
}

extension CleanupWorkspaceModelTests {
    private func makeWorkspace(
        analysisService: any PhotoAnalysisService = MockPhotoAnalysisService(),
        repository: any PhotoClusterRepository = MockPhotoClusterRepository(),
        reviewRepository: any ClusterReviewStateRepository = MockClusterReviewStateRepository()
    ) -> CleanupWorkspaceModel {
        CleanupWorkspaceModel(
            analysisService: analysisService,
            repository: repository,
            reviewRepository: reviewRepository,
            cleanupCategoryRepository: MockCleanupCategorySnapshotRepository(),
            cleanupSessionRepository: MockCleanupSessionRepository(),
            cleanupHistoryRepository: MockCleanupHistoryRepository(),
            bestShotPersonalizedConfigProvider: BestShotPersonalizedScoringConfigProvider(
                repository: MockBestShotPersonalizationRepository()
            ),
            assetByteSizeRepository: MockAssetByteSizeRepository()
        )
    }
}

private actor FailingReviewStateRepository: ClusterReviewStateRepository {
    func loadReviewState(clusterID _: UUID) async throws -> ClusterReviewState? { nil }

    func loadAllReviewStates() async throws -> [UUID: ClusterReviewState] { [:] }

    func saveReviewState(_: ClusterReviewState) async throws {}

    func deleteReviewState(clusterID _: UUID) async throws {}

    func deleteAllReviewStates() async throws {
        throw ReviewPersistenceError()
    }
}

private struct ReviewPersistenceError: LocalizedError {
    var errorDescription: String? { "Review persistence failed" }
}

/// Mutates the repository's library fingerprint from inside
/// `analyzePhotoLibrary`, simulating a photo added or removed while Vision
/// analysis is reading the library — after a scan would have captured its
/// fingerprint early, but before clusters are persisted.
private actor MidScanFingerprintMutatingAnalysisService: PhotoAnalysisService {
    private let repository: MockPhotoClusterRepository
    private let mutatedToken: Data
    private let mutatedImageAssetCount: Int
    private let delegate = MockPhotoAnalysisService()

    init(repository: MockPhotoClusterRepository, mutatedToken: Data, mutatedImageAssetCount: Int) {
        self.repository = repository
        self.mutatedToken = mutatedToken
        self.mutatedImageAssetCount = mutatedImageAssetCount
    }

    func analyzePhotoLibrary(
        sensitivity: Float,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [PhotoCluster] {
        await repository.setLibraryFingerprint(
            token: mutatedToken,
            imageAssetCount: mutatedImageAssetCount
        )
        return try await delegate.analyzePhotoLibrary(sensitivity: sensitivity, progress: progress)
    }

    func summarizeCleanupCategories() async throws -> [CleanupCategorySummary] {
        try await delegate.summarizeCleanupCategories()
    }

    func refreshCleanupCategories(
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [CleanupCategorySummary] {
        try await delegate.refreshCleanupCategories(progress: progress)
    }

    func loadAssets(for category: CleanupCategoryKind) async throws -> [PHAsset] {
        try await delegate.loadAssets(for: category)
    }

    func calculateSimilarity(asset1: PHAsset, asset2: PHAsset) async throws -> Float {
        try await delegate.calculateSimilarity(asset1: asset1, asset2: asset2)
    }
}

private final class ObservationChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var hasChanged: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func recordChange() {
        lock.lock()
        storage = true
        lock.unlock()
    }
}
