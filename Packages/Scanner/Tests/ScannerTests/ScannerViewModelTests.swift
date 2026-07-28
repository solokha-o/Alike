import Cleanup
import Core
import Foundation
import Photos
import XCTest
@testable import Scanner

@MainActor
final class ScannerViewModelTests: XCTestCase {
    func testInitialStateIsIdleWithFullFreeAllowance() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.gridColumns, 3)
        XCTAssertEqual(viewModel.remainingFreeScans, PremiumAccessPolicy.monthlyFreeScanLimit)
    }

    func testDuplicateScanningProgressDoesNotRepublishState() {
        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.publishScanningProgress(0.25))
        XCTAssertFalse(viewModel.publishScanningProgress(0.25))
        XCTAssertTrue(viewModel.publishScanningProgress(0.5))
        XCTAssertEqual(viewModel.state, .scanning(progress: 0.5))
    }

    func testLoadMigratesCurrentMonthWorkspaceBaselineIntoUsage() async {
        let date = makeDate(year: 2026, month: 7, day: 15)
        let repository = MockPhotoClusterRepository()
        await repository.setGetLastScanDateResult(date)
        let workspace = makeWorkspace(repository: repository)
        let usage = TestScanUsageRepository()
        let viewModel = makeViewModel(workspace: workspace, usage: usage, now: { date })

        await viewModel.load()

        XCTAssertEqual(viewModel.monthlyScanUsage?.completedScanCount, 1)
        XCTAssertEqual(viewModel.remainingFreeScans, 2)
        XCTAssertEqual(viewModel.state, .completed(ScanSummary(
            clusterCount: 0,
            cleanupCategoryCandidateCount: 0,
            estimatedSavingsBytes: 0,
            completedAt: date
        )))
    }

    func testLoadResetsStaleMonthlyUsage() async {
        let july = makeDate(year: 2026, month: 7, day: 31)
        let august = makeDate(year: 2026, month: 8, day: 1)
        let usage = TestScanUsageRepository(usage: makeUsage(count: 3, date: july))
        let viewModel = makeViewModel(usage: usage, now: { august })

        await viewModel.load()

        XCTAssertEqual(viewModel.remainingFreeScans, 3)
        XCTAssertEqual(viewModel.monthlyScanUsage?.completedScanCount, 0)
    }

    func testStartScanningResetsMonthlyAllowanceWithoutRecreatingViewModel() async {
        let july = makeDate(year: 2026, month: 7, day: 31)
        let august = makeDate(year: 2026, month: 8, day: 1)
        let clock = TestClock(july)
        let usage = TestScanUsageRepository(usage: makeUsage(count: 3, date: july))
        let analysis = MockPhotoAnalysisService()
        let viewModel = makeViewModel(
            workspace: makeWorkspace(analysis: analysis),
            usage: usage,
            now: { clock.now }
        )

        await viewModel.load()
        XCTAssertEqual(viewModel.remainingFreeScans, 0)

        clock.now = august
        let decision = await viewModel.startScanning()
        let recordCallCount = await usage.recordCallCount()
        XCTAssertEqual(decision, .allowed)
        XCTAssertEqual(viewModel.remainingFreeScans, 2)
        XCTAssertEqual(recordCallCount, 1)
    }

    func testDeniedAdmissionDoesNotStartWorkspaceScan() async {
        let analysis = MockPhotoAnalysisService()
        let usage = TestScanUsageRepository(usage: makeUsage(count: 3, date: Date()))
        let viewModel = makeViewModel(workspace: makeWorkspace(analysis: analysis), usage: usage)

        let decision = await viewModel.startScanning()
        let didAnalyze = await analysis.didCallAnalyzePhotoLibrary
        let recordCallCount = await usage.recordCallCount()
        XCTAssertEqual(decision, .requiresPremium)
        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertFalse(didAnalyze)
        XCTAssertEqual(recordCallCount, 0)
    }

    func testSuccessfulScanRecordsAllowanceAndMapsCompletionState() async {
        let analysis = MockPhotoAnalysisService()
        let cluster = makeCluster()
        let category = CleanupCategorySummary(
            kind: .screenshots,
            assetCount: 2,
            estimatedSavingsBytes: 1_024
        )
        await analysis.setAnalyzePhotoLibraryResult(.success([cluster]))
        await analysis.setRefreshCleanupCategoriesResult(.success([category]))
        let usage = TestScanUsageRepository()
        let viewModel = makeViewModel(workspace: makeWorkspace(analysis: analysis), usage: usage)

        let decision = await viewModel.startScanning()
        let recordCallCount = await usage.recordCallCount()

        XCTAssertEqual(decision, .allowed)
        XCTAssertEqual(recordCallCount, 1)
        XCTAssertEqual(viewModel.remainingFreeScans, 2)
        XCTAssertEqual(viewModel.state, .completed(ScanSummary(
            clusterCount: 1,
            cleanupCategoryCandidateCount: 2,
            estimatedSavingsBytes: 1_024,
            completedAt: viewModel.workspace.lastScanSummary!.completedAt
        )))
    }

    func testFailedScanDoesNotConsumeAllowanceAndKeepsLastGoodWorkspaceContent() async {
        let repository = MockPhotoClusterRepository()
        let existing = makeCluster()
        await repository.setGetLastScanDateResult(Date())
        await repository.setLoadClustersResult(.success([existing]))
        let analysis = MockPhotoAnalysisService()
        await analysis.setAnalyzePhotoLibraryResult(.failure(TestError()))
        let usage = TestScanUsageRepository()
        let workspace = makeWorkspace(analysis: analysis, repository: repository)
        let viewModel = makeViewModel(workspace: workspace, usage: usage)

        await viewModel.load()
        let decision = await viewModel.startScanning()
        let recordCallCount = await usage.recordCallCount()

        XCTAssertEqual(decision, .allowed)
        XCTAssertEqual(recordCallCount, 0)
        XCTAssertEqual(workspace.clusters.map(\.id), [existing.id])
        XCTAssertEqual(viewModel.librarySummary?.clusterCount, 1)
        guard case .error = viewModel.state else {
            return XCTFail("Expected scan failure to map to Scanner.State.error")
        }
    }

    func testConcurrentStartsShareOneAdmissionAndWorkspaceScan() async {
        let analysis = SuspendedPhotoAnalysisService()
        let usage = TestScanUsageRepository(usage: makeUsage(count: 2, date: Date()))
        let viewModel = makeViewModel(workspace: makeWorkspace(analysis: analysis), usage: usage)

        let first = Task { await viewModel.startScanning() }
        await analysis.waitUntilAnalyzeCallCount(1)
        let second = Task { await viewModel.startScanning() }
        await Task.yield()
        await analysis.resumeNext(returning: [])

        let firstDecision = await first.value
        let secondDecision = await second.value
        let analyzeCallCount = await analysis.currentAnalyzeCallCount()
        let recordCallCount = await usage.recordCallCount()
        XCTAssertEqual(firstDecision, .allowed)
        XCTAssertEqual(secondDecision, .allowed)
        XCTAssertEqual(analyzeCallCount, 1)
        XCTAssertEqual(recordCallCount, 1)
    }

    func testJoiningReconciliationScanDoesNotConsumeUserScanAllowance() async {
        let analysis = SuspendedPhotoAnalysisService()
        let usage = TestScanUsageRepository(usage: makeUsage(count: 2, date: Date()))
        let workspace = makeWorkspace(analysis: analysis)
        let viewModel = makeViewModel(workspace: workspace, usage: usage)
        let completion = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 1,
            estimatedSavingsBytes: 512
        )

        let reconciliation = Task {
            await workspace.reconcile(after: completion, sensitivity: .medium)
        }
        await analysis.waitUntilAnalyzeCallCount(1)
        let scanner = Task { await viewModel.startScanning() }
        await Task.yield()
        await analysis.resumeNext(returning: [])

        let scannerDecision = await scanner.value
        await reconciliation.value
        let recordCallCount = await usage.recordCallCount()

        XCTAssertEqual(scannerDecision, .allowed)
        XCTAssertEqual(recordCallCount, 0)
        guard case .completed = viewModel.state else {
            return XCTFail("Expected Scanner to map the joined reconciliation result to completion")
        }
    }

    func testUsefulFreeScanPublishesOneContextualOfferAndConsumptionClearsIt() async {
        let analysis = MockPhotoAnalysisService()
        await analysis.setAnalyzePhotoLibraryResult(.success([makeCluster()]))
        let prompts = MockPremiumPromptHistoryRepository()
        let viewModel = makeViewModel(
            workspace: makeWorkspace(analysis: analysis),
            premiumAccess: TestPremiumAccess(isPremium: false, source: .verified),
            prompts: prompts
        )

        _ = await viewModel.startScanning()
        let claimCallCount = await prompts.claimCallCount

        XCTAssertEqual(viewModel.pendingPostScanPremiumOffer?.similarClusterCount, 1)
        viewModel.consumePostScanPremiumOffer()
        XCTAssertNil(viewModel.pendingPostScanPremiumOffer)
        XCTAssertEqual(claimCallCount, 1)
    }

    func testEmptyOrPremiumOrUnknownEntitlementScansDoNotPublishOffer() async {
        let emptyAnalysis = MockPhotoAnalysisService()
        let emptyViewModel = makeViewModel(
            workspace: makeWorkspace(analysis: emptyAnalysis),
            premiumAccess: TestPremiumAccess(isPremium: false, source: .verified)
        )
        _ = await emptyViewModel.startScanning()
        XCTAssertNil(emptyViewModel.pendingPostScanPremiumOffer)

        let premiumAnalysis = MockPhotoAnalysisService()
        await premiumAnalysis.setAnalyzePhotoLibraryResult(.success([makeCluster()]))
        let premiumViewModel = makeViewModel(
            workspace: makeWorkspace(analysis: premiumAnalysis),
            premiumAccess: TestPremiumAccess(isPremium: true, source: .verified)
        )
        _ = await premiumViewModel.startScanning()
        XCTAssertNil(premiumViewModel.pendingPostScanPremiumOffer)

        let unknownAnalysis = MockPhotoAnalysisService()
        await unknownAnalysis.setAnalyzePhotoLibraryResult(.success([makeCluster()]))
        let unknownViewModel = makeViewModel(
            workspace: makeWorkspace(analysis: unknownAnalysis),
            premiumAccess: TestPremiumAccess(isPremium: false, source: .unknown)
        )
        _ = await unknownViewModel.startScanning()
        XCTAssertNil(unknownViewModel.pendingPostScanPremiumOffer)
    }
}

private extension ScannerViewModelTests {
    func makeViewModel(
        workspace: CleanupWorkspaceModel? = nil,
        usage: TestScanUsageRepository = TestScanUsageRepository(),
        premiumAccess: any PremiumAccessControlling = TestPremiumAccess(),
        prompts: any PremiumPromptHistoryRepository = MockPremiumPromptHistoryRepository(),
        now: @escaping @Sendable () -> Date = Date.init
    ) -> ScannerViewModel {
        ScannerViewModel(
            workspace: workspace ?? makeWorkspace(),
            premiumAccess: premiumAccess,
            scanUsageRepository: usage,
            premiumPromptHistoryRepository: prompts,
            calendar: utcCalendar,
            now: now
        )
    }

    func makeWorkspace(
        analysis: any PhotoAnalysisService = MockPhotoAnalysisService(),
        repository: any PhotoClusterRepository = MockPhotoClusterRepository()
    ) -> CleanupWorkspaceModel {
        CleanupWorkspaceModel(
            analysisService: analysis,
            repository: repository,
            reviewRepository: MockClusterReviewStateRepository(),
            cleanupCategoryRepository: MockCleanupCategorySnapshotRepository(),
            cleanupSessionRepository: MockCleanupSessionRepository(),
            cleanupHistoryRepository: MockCleanupHistoryRepository()
        )
    }

    func makeCluster() -> PhotoCluster {
        PhotoCluster(
            id: UUID(),
            assets: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            averageSimilarity: 0.92
        )
    }

    func makeDate(year: Int, month: Int, day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func makeUsage(count: Int, date: Date) -> MonthlyScanUsage {
        let start = utcCalendar.date(from: utcCalendar.dateComponents([.year, .month], from: date))!
        return MonthlyScanUsage(
            periodStart: start,
            nextResetDate: utcCalendar.date(byAdding: .month, value: 1, to: start)!,
            completedScanCount: count
        )
    }

    var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private struct TestError: LocalizedError {
    var errorDescription: String? { "Test scan failure" }
}

private final class TestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) { self.now = now }
}

private actor TestScanUsageRepository: ScanUsageRepository {
    private var usage: MonthlyScanUsage?
    private var recordCalls = 0

    init(usage: MonthlyScanUsage? = nil) { self.usage = usage }

    func loadMonthlyUsage(at date: Date) -> MonthlyScanUsage? {
        guard let currentUsage = usage else { return nil }
        guard calendar.isDate(currentUsage.periodStart, equalTo: date, toGranularity: .month) else {
            let reset = makeUsage(count: 0, date: date)
            self.usage = reset
            return reset
        }
        return currentUsage
    }

    func initializeMonthlyUsage(_ usage: MonthlyScanUsage) {
        guard self.usage == nil else { return }
        self.usage = usage
    }

    func recordCompletedScan(at date: Date) -> MonthlyScanUsage {
        recordCalls += 1
        let completed = (loadMonthlyUsage(at: date)?.completedScanCount ?? 0) + 1
        let updated = makeUsage(count: completed, date: date)
        usage = updated
        return updated
    }

    func recordCallCount() -> Int { recordCalls }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeUsage(count: Int, date: Date) -> MonthlyScanUsage {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        return MonthlyScanUsage(
            periodStart: start,
            nextResetDate: calendar.date(byAdding: .month, value: 1, to: start)!,
            completedScanCount: count
        )
    }
}

@MainActor
private struct TestPremiumAccess: PremiumAccessControlling {
    let entitlementState: PremiumEntitlementState

    init(isPremium: Bool = false, source: PremiumEntitlementSource = .verified) {
        entitlementState = PremiumEntitlementState(isPremium: isPremium, source: source)
    }

    func access(to feature: PremiumFeature, context: PremiumAccessContext) -> PremiumAccessDecision {
        PremiumAccessPolicy.decision(for: feature, context: context, isPremium: entitlementState.isPremium)
    }
}

private actor SuspendedPhotoAnalysisService: PhotoAnalysisService {
    private var continuation: CheckedContinuation<[PhotoCluster], Error>?
    private var analyzeCalls = 0

    func analyzePhotoLibrary(
        sensitivity: Float,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [PhotoCluster] {
        analyzeCalls += 1
        progress(0.5)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func summarizeCleanupCategories() async throws -> [CleanupCategorySummary] { [] }
    func refreshCleanupCategories() async throws -> [CleanupCategorySummary] { [] }
    func loadAssets(for category: CleanupCategoryKind) async throws -> [PHAsset] { [] }
    func calculateSimilarity(asset1: PHAsset, asset2: PHAsset) async throws -> Float { 0 }

    func waitUntilAnalyzeCallCount(_ expectedCount: Int) async {
        while analyzeCalls < expectedCount { await Task.yield() }
    }

    func resumeNext(returning clusters: [PhotoCluster]) {
        continuation?.resume(returning: clusters)
        continuation = nil
    }

    func currentAnalyzeCallCount() -> Int { analyzeCalls }
}
