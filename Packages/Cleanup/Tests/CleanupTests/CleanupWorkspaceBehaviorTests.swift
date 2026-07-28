import Cleanup
import Core
import Photos
import XCTest

@MainActor
final class CleanupWorkspaceBehaviorTests: XCTestCase {
    func testCompletedEmptyCacheIsDistinctFromNeverScanned() async {
        let neverScannedRepository = MockPhotoClusterRepository()
        let neverScanned = makeWorkspace(repository: neverScannedRepository)

        await neverScanned.loadCachedContent()

        XCTAssertEqual(neverScanned.contentState, .neverScanned)
        XCTAssertNil(neverScanned.content)

        let completedRepository = MockPhotoClusterRepository()
        await completedRepository.setGetLastScanDateResult(Date(timeIntervalSince1970: 1))
        let completed = makeWorkspace(repository: completedRepository)

        await completed.loadCachedContent()

        XCTAssertEqual(completed.content?.clusters, [])
        XCTAssertEqual(completed.contentState, .content(completed.content!))
    }

    func testFailedRefreshPreservesLastGoodContent() async throws {
        let analysis = ControlledAnalysisService()
        let workspace = makeWorkspace(analysisService: analysis)
        let initialCluster = PhotoCluster(id: UUID(), assets: [], createdAt: .distantPast)

        let initialScan = Task { @MainActor in
            try await workspace.scan(sensitivity: .medium)
        }
        await analysis.waitUntilAnalyzeStarts()
        await analysis.succeed(with: [initialCluster])
        _ = try await initialScan.value

        let failedScan = Task { @MainActor in
            try await workspace.scan(sensitivity: .medium)
        }
        await analysis.waitUntilAnalyzeStarts(expectedCallCount: 2)
        await analysis.fail(with: TestError.failedRefresh)

        do {
            _ = try await failedScan.value
            XCTFail("The refresh should fail")
        } catch {
            XCTAssertEqual(error as? TestError, .failedRefresh)
        }

        XCTAssertEqual(workspace.clusters, [initialCluster])
        XCTAssertEqual(workspace.contentState, .content(workspace.content!))
        XCTAssertEqual(
            workspace.scanOperation,
            .failed(message: TestError.failedRefresh.localizedDescription, purpose: .userInitiated)
        )
    }

    func testConcurrentScanRequestsJoinOneUnderlyingOperation() async throws {
        let analysis = ControlledAnalysisService()
        let workspace = makeWorkspace(analysisService: analysis)
        let cluster = PhotoCluster(id: UUID(), assets: [])

        let first = Task { @MainActor in try await workspace.scan(sensitivity: .medium) }
        await analysis.waitUntilAnalyzeStarts()
        let second = Task { @MainActor in try await workspace.scan(sensitivity: .high) }
        await Task.yield()

        let callsWhileInFlight = await analysis.analyzeCallCount()
        XCTAssertEqual(callsWhileInFlight, 1)

        await analysis.succeed(with: [cluster])
        let firstSummary = try await first.value
        let secondSummary = try await second.value

        XCTAssertEqual(firstSummary, secondSummary)
        XCTAssertEqual(firstSummary.clusterCount, 1)
        let totalCalls = await analysis.analyzeCallCount()
        XCTAssertEqual(totalCalls, 1)
    }

    func testScanProgressNeverMovesBackward() async throws {
        let analysis = ControlledAnalysisService()
        let workspace = makeWorkspace(analysisService: analysis)
        let scan = Task { @MainActor in try await workspace.scan(sensitivity: .medium) }
        await analysis.waitUntilAnalyzeStarts()

        await analysis.sendProgress(1)
        await waitForProgress(in: workspace, toReach: 0.8)
        await analysis.sendProgress(0.4)
        await Task.yield()

        XCTAssertEqual(workspace.scanOperation.progress, 0.8)

        await analysis.succeed(with: [])
        _ = try await scan.value
    }

    func testFailedReconciliationKeepsLastGoodWorkspaceContent() async throws {
        let analysis = ControlledAnalysisService()
        let workspace = makeWorkspace(analysisService: analysis)
        let cluster = PhotoCluster(id: UUID(), assets: [])

        let scan = Task { @MainActor in try await workspace.scan(sensitivity: .medium) }
        await analysis.waitUntilAnalyzeStarts()
        await analysis.succeed(with: [cluster])
        _ = try await scan.value

        let record = CleanupCompletionRecord(
            sourceClusterID: cluster.id,
            deletedCount: 1,
            estimatedSavingsBytes: 100
        )
        let reconciliation = Task { @MainActor in
            await workspace.reconcile(after: record, sensitivity: .medium)
        }
        await analysis.waitUntilAnalyzeStarts(expectedCallCount: 2)
        await analysis.fail(with: TestError.failedRefresh)
        await reconciliation.value

        XCTAssertEqual(workspace.clusters, [cluster])
        XCTAssertEqual(workspace.contentState, .content(workspace.content!))
        XCTAssertEqual(
            workspace.reconciliationState,
            .failed(
                record,
                message: "The photos were deleted, but the library refresh failed. Run a new scan to refresh your results."
            )
        )
    }

    func testStaleCachedLoadCannotReplaceCompletedScan() async throws {
        let staleCluster = PhotoCluster(id: UUID(), assets: [], createdAt: .distantPast)
        let freshCluster = PhotoCluster(id: UUID(), assets: [], createdAt: .now)
        let repository = ControlledPhotoClusterRepository(
            initialClusters: [],
            lastScanDate: .distantPast,
            blockFirstClusterLoad: true
        )
        let analysis = ControlledAnalysisService()
        let workspace = makeWorkspace(analysisService: analysis, repository: repository)

        let cacheLoad = Task { @MainActor in await workspace.loadCachedContent() }
        await repository.waitUntilFirstClusterLoadStarts()

        let scan = Task { @MainActor in try await workspace.scan(sensitivity: .medium) }
        await analysis.waitUntilAnalyzeStarts()
        await analysis.succeed(with: [freshCluster])
        _ = try await scan.value

        await repository.resumeFirstClusterLoad(with: [staleCluster])
        await cacheLoad.value

        XCTAssertEqual(workspace.clusters, [freshCluster])
        XCTAssertEqual(workspace.contentState, .content(workspace.content!))
    }

    func testRepeatedCachedLoadsJoinOneRepositoryRead() async {
        let repository = ControlledPhotoClusterRepository(
            initialClusters: [],
            lastScanDate: .distantPast,
            blockFirstClusterLoad: true
        )
        let workspace = makeWorkspace(repository: repository)

        let firstLoad = Task { @MainActor in await workspace.loadCachedContent() }
        await repository.waitUntilFirstClusterLoadStarts()
        let joinedLoad = Task { @MainActor in await workspace.loadCachedContent() }
        await Task.yield()

        let inFlightLoadCount = await repository.loadClustersCallCount()
        XCTAssertEqual(inFlightLoadCount, 1)

        await repository.resumeFirstClusterLoad(with: [])
        await firstLoad.value
        await joinedLoad.value
        await workspace.loadCachedContent()

        let completedLoadCount = await repository.loadClustersCallCount()
        XCTAssertEqual(completedLoadCount, 1)
    }

    func testStaleGalleryChangeResultCannotReenableRescanAfterSuccessfulScan() async throws {
        let repository = ControlledPhotoClusterRepository(
            initialClusters: [],
            lastScanDate: .distantPast,
            blockGalleryChange: true
        )
        let analysis = ControlledAnalysisService()
        let workspace = makeWorkspace(analysisService: analysis, repository: repository)

        await workspace.loadCachedContent()
        let galleryCheck = Task { @MainActor in await workspace.checkForGalleryChanges() }
        await repository.waitUntilGalleryChangeCheckStarts()

        let scan = Task { @MainActor in try await workspace.scan(sensitivity: .medium) }
        await analysis.waitUntilAnalyzeStarts()
        await analysis.succeed(with: [])
        _ = try await scan.value

        await repository.resumeGalleryChangeCheck(with: true)
        let galleryChangeWasCommitted = await galleryCheck.value

        XCTAssertFalse(galleryChangeWasCommitted)
        XCTAssertFalse(workspace.shouldShowRescanPrompt)
    }

    func testQueuedReconciliationProcessesOnlyLatestWaitingRecord() async {
        let analysis = ControlledAnalysisService()
        let workspace = makeWorkspace(analysisService: analysis)
        let firstRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 1,
            estimatedSavingsBytes: 100
        )
        let supersededRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 2,
            estimatedSavingsBytes: 200
        )
        let latestRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 3,
            estimatedSavingsBytes: 300
        )

        let firstReconciliation = Task { @MainActor in
            await workspace.reconcile(after: firstRecord, sensitivity: .medium)
        }
        await analysis.waitUntilAnalyzeStarts()

        await workspace.reconcile(after: supersededRecord, sensitivity: .low)
        await workspace.reconcile(after: latestRecord, sensitivity: .high)
        await analysis.succeed(with: [])

        await analysis.waitUntilAnalyzeStarts(expectedCallCount: 2)
        await analysis.succeed(with: [])
        await firstReconciliation.value
        let analysisCallCount = await analysis.analyzeCallCount()

        XCTAssertEqual(workspace.reconciliationState, .success(latestRecord))
        XCTAssertEqual(analysisCallCount, 2)
    }
}

private extension CleanupWorkspaceBehaviorTests {
    func makeWorkspace(
        analysisService: any PhotoAnalysisService = MockPhotoAnalysisService(),
        repository: any PhotoClusterRepository = MockPhotoClusterRepository()
    ) -> CleanupWorkspaceModel {
        CleanupWorkspaceModel(
            analysisService: analysisService,
            repository: repository,
            reviewRepository: MockClusterReviewStateRepository(),
            cleanupCategoryRepository: MockCleanupCategorySnapshotRepository(),
            cleanupSessionRepository: MockCleanupSessionRepository(),
            cleanupHistoryRepository: MockCleanupHistoryRepository()
        )
    }

    func waitForProgress(in workspace: CleanupWorkspaceModel, toReach expected: Double) async {
        for _ in 0..<20 {
            if workspace.scanOperation.progress == expected { return }
            await Task.yield()
        }
        XCTFail("Scan progress did not reach \(expected)")
    }
}

private enum TestError: Error, LocalizedError, Equatable {
    case failedRefresh

    var errorDescription: String? { "Refresh failed" }
}

private actor ControlledAnalysisService: PhotoAnalysisService {
    private var analyzeCallCountStorage = 0
    private var analyzeStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var analysisContinuation: CheckedContinuation<[PhotoCluster], Error>?
    private var progress: (@Sendable (Double) -> Void)?

    func analyzePhotoLibrary(
        sensitivity: Float,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [PhotoCluster] {
        analyzeCallCountStorage += 1
        self.progress = progress
        let waiters = analyzeStartWaiters
        analyzeStartWaiters.removeAll()
        waiters.forEach { $0.resume() }

        return try await withCheckedThrowingContinuation { continuation in
            analysisContinuation = continuation
        }
    }

    func summarizeCleanupCategories() async throws -> [CleanupCategorySummary] { [] }

    func refreshCleanupCategories(
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [CleanupCategorySummary] {
        progress(0)
        progress(1)
        return []
    }

    func loadAssets(for category: CleanupCategoryKind) async throws -> [PHAsset] { [] }

    func calculateSimilarity(asset1: PHAsset, asset2: PHAsset) async throws -> Float { 1 }

    func waitUntilAnalyzeStarts(expectedCallCount: Int = 1) async {
        guard analyzeCallCountStorage < expectedCallCount else { return }
        await withCheckedContinuation { continuation in
            analyzeStartWaiters.append(continuation)
        }
    }

    func analyzeCallCount() -> Int { analyzeCallCountStorage }

    func sendProgress(_ value: Double) {
        progress?(value)
    }

    func succeed(with clusters: [PhotoCluster]) {
        let continuation = analysisContinuation
        analysisContinuation = nil
        continuation?.resume(returning: clusters)
    }

    func fail(with error: TestError) {
        let continuation = analysisContinuation
        analysisContinuation = nil
        continuation?.resume(throwing: error)
    }
}

private actor ControlledPhotoClusterRepository: PhotoClusterRepository {
    private var clusters: [PhotoCluster]
    private var lastScanDate: Date?
    private let blockFirstClusterLoad: Bool
    private let blockGalleryChange: Bool
    private var clusterLoadCount = 0
    private var firstClusterLoadContinuation: CheckedContinuation<[PhotoCluster], Never>?
    private var firstClusterLoadWaiters: [CheckedContinuation<Void, Never>] = []
    private var galleryChangeContinuation: CheckedContinuation<Bool, Never>?
    private var galleryChangeWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        initialClusters: [PhotoCluster],
        lastScanDate: Date?,
        blockFirstClusterLoad: Bool = false,
        blockGalleryChange: Bool = false
    ) {
        clusters = initialClusters
        self.lastScanDate = lastScanDate
        self.blockFirstClusterLoad = blockFirstClusterLoad
        self.blockGalleryChange = blockGalleryChange
    }

    func loadClusters() async throws -> [PhotoCluster] {
        clusterLoadCount += 1
        guard blockFirstClusterLoad, clusterLoadCount == 1 else { return clusters }

        return await withCheckedContinuation { continuation in
            firstClusterLoadContinuation = continuation
            let waiters = firstClusterLoadWaiters
            firstClusterLoadWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func loadClustersCallCount() -> Int {
        clusterLoadCount
    }

    func loadClusterSnapshots() async throws -> [PhotoClusterSnapshot] { [] }

    func saveClusters(_ clusters: [PhotoCluster]) async throws {
        self.clusters = clusters
    }

    func deleteAllClusters() async throws {
        clusters = []
    }

    func getLastScanDate() async -> Date? { lastScanDate }

    func updateLastScanDate(_ date: Date) async throws {
        lastScanDate = date
    }

    func hasGalleryChanged() async -> Bool {
        guard blockGalleryChange else { return false }

        return await withCheckedContinuation { continuation in
            galleryChangeContinuation = continuation
            let waiters = galleryChangeWaiters
            galleryChangeWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilFirstClusterLoadStarts() async {
        guard firstClusterLoadContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            firstClusterLoadWaiters.append(continuation)
        }
    }

    func resumeFirstClusterLoad(with clusters: [PhotoCluster]) {
        let continuation = firstClusterLoadContinuation
        firstClusterLoadContinuation = nil
        continuation?.resume(returning: clusters)
    }

    func waitUntilGalleryChangeCheckStarts() async {
        guard galleryChangeContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            galleryChangeWaiters.append(continuation)
        }
    }

    func resumeGalleryChangeCheck(with result: Bool) {
        let continuation = galleryChangeContinuation
        galleryChangeContinuation = nil
        continuation?.resume(returning: result)
    }
}
