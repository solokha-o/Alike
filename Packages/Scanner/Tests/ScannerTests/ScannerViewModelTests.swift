import XCTest
import Foundation
import Photos
import Core
import Cleanup
@testable import Scanner

@MainActor
final class ScannerViewModelTests: XCTestCase {
    var viewModel: ScannerViewModel!
    var mockAnalysisService: MockPhotoAnalysisService!
    var mockRepository: MockPhotoClusterRepository!
    var mockReviewRepository: MockClusterReviewStateRepository!
    var mockCleanupCategoryRepository: MockCleanupCategorySnapshotRepository!
    var mockCleanupSessionRepository: MockCleanupSessionRepository!
    var mockCleanupService: MockPhotoCleanupService!
    var mockCleanupHistoryRepository: MockCleanupHistoryRepository!
    var scanUsageRepository: MockScanUsageRepository!
    var premiumPromptHistoryRepository: MockPremiumPromptHistoryRepository!
    var premiumAccess: MockPremiumAccessController!
    
    override func setUp() async throws {
        mockAnalysisService = MockPhotoAnalysisService()
        mockRepository = MockPhotoClusterRepository()
        mockReviewRepository = MockClusterReviewStateRepository()
        mockCleanupCategoryRepository = MockCleanupCategorySnapshotRepository()
        mockCleanupSessionRepository = MockCleanupSessionRepository()
        mockCleanupService = MockPhotoCleanupService()
        mockCleanupHistoryRepository = MockCleanupHistoryRepository()
        scanUsageRepository = MockScanUsageRepository()
        premiumPromptHistoryRepository = MockPremiumPromptHistoryRepository()
        premiumAccess = MockPremiumAccessController()
        viewModel = makeViewModel(premiumAccess: premiumAccess)
    }
    
    override func tearDown() async throws {
        viewModel = nil
        mockAnalysisService = nil
        mockRepository = nil
        mockReviewRepository = nil
        mockCleanupCategoryRepository = nil
        mockCleanupSessionRepository = nil
        mockCleanupService = nil
        mockCleanupHistoryRepository = nil
        scanUsageRepository = nil
        premiumPromptHistoryRepository = nil
        premiumAccess = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitialState() {
        if case .idle = viewModel.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .idle state")
        }
    }
    
    func testInitialGridColumns() {
        XCTAssertEqual(viewModel.gridColumns, 3)
    }

    func testDeniedScanDoesNotCreateALIReaction() async {
        await scanUsageRepository.setCompletedScanCount(PremiumAccessPolicy.monthlyFreeScanLimit)

        let decision = await viewModel.startScanning()

        XCTAssertEqual(decision, .requiresPremium)
        XCTAssertNil(viewModel.currentALIReaction)
    }

    func testScanReactionCountsClustersAndCleanupCategoryCandidates() async {
        await mockAnalysisService.setAnalyzePhotoLibraryResult(
            .success([createMockCluster(photoCount: 2)])
        )
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([
            CleanupCategorySummary(
                kind: .screenshots,
                assetCount: 3,
                estimatedSavingsBytes: 1_024
            )
        ]))

        await viewModel.startScanning()

        XCTAssertEqual(viewModel.currentALIReaction?.state, .resultsFound(candidateCount: 4))
        XCTAssertEqual(viewModel.currentALIReaction?.persistence, .oneShot)
    }

    func testSuccessfulEmptyScanPublishesNoResults() async {
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))

        await viewModel.startScanning()

        XCTAssertEqual(viewModel.currentALIReaction?.state, .noResults)
    }

    func testCleanupCategoryFailureDoesNotClaimNoResults() async {
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.failure(TestError()))

        await viewModel.startScanning()

        XCTAssertEqual(
            viewModel.currentALIReaction?.state,
            .recoverableError(ALIErrorContext(operation: .scan))
        )
        if case .error = viewModel.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected category failure to preserve the error path")
        }
    }

    func testSuccessfulScanIncrementsUsageExactlyOnce() async {
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))

        let decision = await viewModel.startScanning()
        let count = await scanUsageRepository.currentCount()
        let recordCalls = await scanUsageRepository.recordCallCount()

        XCTAssertEqual(decision, .allowed)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(recordCalls, 1)
    }

    func testFailedScanDoesNotConsumeAllowance() async {
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.failure(TestError()))

        let decision = await viewModel.startScanning()
        let count = await scanUsageRepository.currentCount()
        let recordCalls = await scanUsageRepository.recordCallCount()

        XCTAssertEqual(decision, .allowed)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(recordCalls, 0)
    }

    func testFirstUsefulScanPublishesOnePersistedPremiumOffer() async {
        viewModel = makeViewModel(
            premiumAccess: MutableEntitlementPremiumAccessController(
                entitlementState: PremiumEntitlementState(isPremium: false, source: .verified)
            )
        )
        let cluster = createMockCluster(photoCount: 2)
        let category = CleanupCategorySummary(
            kind: .screenshots,
            assetCount: 3,
            estimatedSavingsBytes: 4_096
        )
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([cluster]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([category]))

        await viewModel.startScanning()

        XCTAssertEqual(viewModel.pendingPostScanPremiumOffer?.similarClusterCount, 1)
        XCTAssertEqual(viewModel.pendingPostScanPremiumOffer?.cleanupCategoryCandidateCount, 3)
        XCTAssertEqual(viewModel.pendingPostScanPremiumOffer?.estimatedSavingsBytes, 4_096)

        viewModel.consumePostScanPremiumOffer()
        await viewModel.startScanning()
        let claimCallCount = await premiumPromptHistoryRepository.claimCallCount
        XCTAssertNil(viewModel.pendingPostScanPremiumOffer)
        XCTAssertEqual(claimCallCount, 2)
    }

    func testEmptyScanDefersPremiumOfferUntilUsefulScan() async {
        viewModel = makeViewModel(
            premiumAccess: MutableEntitlementPremiumAccessController(
                entitlementState: PremiumEntitlementState(isPremium: false, source: .verified)
            )
        )
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))
        await viewModel.startScanning()
        XCTAssertNil(viewModel.pendingPostScanPremiumOffer)

        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([
            CleanupCategorySummary(kind: .blurredPhotos, assetCount: 1, estimatedSavingsBytes: 512)
        ]))
        await viewModel.startScanning()

        let claimCallCount = await premiumPromptHistoryRepository.claimCallCount
        XCTAssertEqual(viewModel.pendingPostScanPremiumOffer?.cleanupCategoryCandidateCount, 1)
        XCTAssertEqual(claimCallCount, 1)
    }

    func testPremiumUserDoesNotReceivePostScanOffer() async {
        viewModel = makeViewModel(
            premiumAccess: MutableEntitlementPremiumAccessController(
                entitlementState: PremiumEntitlementState(isPremium: true, source: .verified)
            )
        )
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([createMockCluster(photoCount: 2)]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))

        await viewModel.startScanning()

        let claimCallCount = await premiumPromptHistoryRepository.claimCallCount
        XCTAssertNil(viewModel.pendingPostScanPremiumOffer)
        XCTAssertEqual(claimCallCount, 0)
    }

    func testUnknownEntitlementDoesNotClaimOrPublishPostScanOffer() async {
        viewModel = makeViewModel(
            premiumAccess: MutableEntitlementPremiumAccessController(entitlementState: .unknown)
        )
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([createMockCluster(photoCount: 2)]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))

        await viewModel.startScanning()

        let claimCallCount = await premiumPromptHistoryRepository.claimCallCount
        XCTAssertNil(viewModel.pendingPostScanPremiumOffer)
        XCTAssertEqual(claimCallCount, 0)
    }

    func testEntitlementBecomingPremiumDuringClaimDoesNotPublishPostScanOffer() async {
        let premiumAccess = MutableEntitlementPremiumAccessController(
            entitlementState: PremiumEntitlementState(isPremium: false, source: .verified)
        )
        let suspendedPromptHistoryRepository = SuspendedPremiumPromptHistoryRepository()
        viewModel = makeViewModel(
            premiumAccess: premiumAccess,
            promptHistoryRepository: suspendedPromptHistoryRepository
        )
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([createMockCluster(photoCount: 2)]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))

        let scan = Task { await viewModel.startScanning() }
        await suspendedPromptHistoryRepository.waitUntilClaimCallCount(1)
        premiumAccess.entitlementState = PremiumEntitlementState(isPremium: true, source: .verified)
        await suspendedPromptHistoryRepository.resumeClaim(returning: true)
        _ = await scan.value

        let claimCallCount = await suspendedPromptHistoryRepository.currentClaimCallCount()
        XCTAssertNil(viewModel.pendingPostScanPremiumOffer)
        XCTAssertEqual(claimCallCount, 1)
    }

    func testEntitlementBecomingUnknownDuringClaimReleasesClaimForLaterFreeOffer() async {
        let premiumAccess = MutableEntitlementPremiumAccessController(
            entitlementState: PremiumEntitlementState(isPremium: false, source: .verified)
        )
        let suspendedPromptHistoryRepository = SuspendedPremiumPromptHistoryRepository()
        viewModel = makeViewModel(
            premiumAccess: premiumAccess,
            promptHistoryRepository: suspendedPromptHistoryRepository
        )
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([createMockCluster(photoCount: 2)]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))

        let scan = Task { await viewModel.startScanning() }
        await suspendedPromptHistoryRepository.waitUntilClaimCallCount(1)
        premiumAccess.entitlementState = .unknown
        await suspendedPromptHistoryRepository.resumeClaim(returning: true)
        _ = await scan.value

        XCTAssertNil(viewModel.pendingPostScanPremiumOffer)
        let releaseCallCount = await suspendedPromptHistoryRepository.currentReleaseCallCount()
        XCTAssertEqual(releaseCallCount, 1)

        premiumAccess.entitlementState = PremiumEntitlementState(isPremium: false, source: .verified)
        let retryScan = Task { await viewModel.startScanning() }
        await suspendedPromptHistoryRepository.waitUntilClaimCallCount(2)
        await suspendedPromptHistoryRepository.resumeClaim(returning: true)
        _ = await retryScan.value

        XCTAssertNotNil(viewModel.pendingPostScanPremiumOffer)
    }

    func testPostCleanupReconciliationDoesNotConsumeUserInitiatedScanAllowance() async {
        await scanUsageRepository.setCompletedScanCount(2)
        await viewModel.loadCachedResults()
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))
        let completionRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 1,
            estimatedSavingsBytes: 512
        )

        await viewModel.handleCleanupCompleted(completionRecord)

        let count = await scanUsageRepository.currentCount()
        let recordCalls = await scanUsageRepository.recordCallCount()
        XCTAssertEqual(count, 2)
        XCTAssertEqual(recordCalls, 0)
        XCTAssertEqual(viewModel.remainingFreeScans, 1)
    }

    func testFourthMonthlyScanRequiresPremiumWithoutChangingResults() async {
        await scanUsageRepository.setCompletedScanCount(3)
        let existing = createMockCluster(photoCount: 2)
        viewModel.state = .results([existing])

        let decision = await viewModel.startScanning()
        let recordCalls = await scanUsageRepository.recordCallCount()

        XCTAssertEqual(decision, .requiresPremium)
        XCTAssertEqual(viewModel.state, .results([existing]))
        XCTAssertEqual(recordCalls, 0)
    }

    func testConcurrentUserInitiatedScansShareOneAdmissionAndAnalysis() async {
        let analysisService = SuspendedPhotoAnalysisService()
        let usageRepository = MockScanUsageRepository(count: 2)
        let serializedViewModel = ScannerViewModel(
            analysisService: analysisService,
            repository: mockRepository,
            reviewRepository: mockReviewRepository,
            cleanupCategoryRepository: mockCleanupCategoryRepository,
            cleanupSessionRepository: mockCleanupSessionRepository,
            cleanupService: mockCleanupService,
            cleanupHistoryRepository: mockCleanupHistoryRepository,
            premiumAccess: premiumAccess,
            scanUsageRepository: usageRepository
        )

        let firstScan = Task { await serializedViewModel.startScanning() }
        await analysisService.waitUntilAnalyzeCallCount(1)
        let resumeAnalysis = Task {
            await Task.yield()
            await analysisService.resumeNext(returning: [])
        }

        let secondDecision = await serializedViewModel.startScanning()
        let firstDecision = await firstScan.value
        await resumeAnalysis.value
        let analyzeCallCount = await analysisService.currentAnalyzeCallCount()
        let maximumConcurrentCount = await analysisService.maximumConcurrentAnalyzeCount()
        let completedScanCount = await usageRepository.currentCount()
        let recordCallCount = await usageRepository.recordCallCount()

        XCTAssertEqual(firstDecision, .allowed)
        XCTAssertEqual(secondDecision, .allowed)
        XCTAssertEqual(analyzeCallCount, 1)
        XCTAssertEqual(maximumConcurrentCount, 1)
        XCTAssertEqual(completedScanCount, 3)
        XCTAssertEqual(recordCallCount, 1)
    }

    func testConcurrentColdStartAdmissionsNeverAuthorizeUnknownUsageAsZero() async {
        let usageRepository = SuspendedScanUsageRepository()
        let storedUsage = makeMonthlyUsage(count: 3, date: Date())
        let coldStartViewModel = ScannerViewModel(
            analysisService: mockAnalysisService,
            repository: mockRepository,
            premiumAccess: premiumAccess,
            scanUsageRepository: usageRepository
        )

        let firstScan = Task { await coldStartViewModel.startScanning() }
        await usageRepository.waitUntilLoadCallCount(1)
        let resumeUsageLoad = Task {
            await Task.yield()
            await usageRepository.resumeNextLoad(returning: storedUsage)
        }

        let secondDecision = await coldStartViewModel.startScanning()
        let firstDecision = await firstScan.value
        await resumeUsageLoad.value
        let loadCallCount = await usageRepository.loadCallCount()
        let didAnalyze = await mockAnalysisService.didCallAnalyzePhotoLibrary

        XCTAssertEqual(firstDecision, .requiresPremium)
        XCTAssertEqual(secondDecision, .requiresPremium)
        XCTAssertEqual(loadCallCount, 1)
        XCTAssertFalse(didAnalyze)
    }

    func testMonthlyScanAllowanceResetsOnFreshLaunchInNewMonth() async {
        let july = Date(timeIntervalSince1970: 1_783_814_400)
        let august = Date(timeIntervalSince1970: 1_786_492_800)
        let usageRepository = MockScanUsageRepository(count: nil)
        await usageRepository.setMonthlyUsage(count: 3, date: july)
        let relaunchedViewModel = ScannerViewModel(
            analysisService: mockAnalysisService,
            repository: mockRepository,
            premiumAccess: premiumAccess,
            scanUsageRepository: usageRepository,
            calendar: Calendar(identifier: .gregorian),
            now: { august }
        )

        await relaunchedViewModel.loadCachedResults()

        XCTAssertEqual(relaunchedViewModel.remainingFreeScans, 3)
    }

    func testMonthlyScanAllowanceResetsWithoutRecreatingViewModel() async {
        let july = makeDate(year: 2026, month: 7, day: 31)
        let august = makeDate(year: 2026, month: 8, day: 1)
        let clock = LockedDateProvider(july)
        let usageRepository = MockScanUsageRepository(count: nil)
        await usageRepository.setMonthlyUsage(count: 3, date: july)
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))
        let persistentViewModel = ScannerViewModel(
            analysisService: mockAnalysisService,
            repository: mockRepository,
            premiumAccess: premiumAccess,
            scanUsageRepository: usageRepository,
            calendar: utcCalendar,
            now: { clock.now() }
        )

        await persistentViewModel.loadCachedResults()
        XCTAssertEqual(persistentViewModel.remainingFreeScans, 0)

        clock.set(august)
        let decision = await persistentViewModel.startScanning()
        let completedScanCount = await usageRepository.currentCount()

        XCTAssertEqual(decision, .allowed)
        XCTAssertEqual(persistentViewModel.remainingFreeScans, 2)
        XCTAssertEqual(completedScanCount, 1)
    }

    func testAdvancedFiltersUsePremiumAccess() {
        XCTAssertTrue(viewModel.isAdvancedFilteringLocked)

        let unlockedViewModel = ScannerViewModel(
            analysisService: mockAnalysisService,
            repository: mockRepository,
            premiumAccess: MockPremiumAccessController(unlockedFeatures: [.advancedFilters]),
            scanUsageRepository: scanUsageRepository
        )

        XCTAssertFalse(unlockedViewModel.isAdvancedFilteringLocked)
    }

    func testPremiumFilterFieldsStopAffectingResultsAfterAccessRevocation() {
        let mutableAccess = MutablePremiumAccessController(unlocksAdvancedFilters: true)
        let revocableViewModel = ScannerViewModel(
            analysisService: mockAnalysisService,
            repository: mockRepository,
            premiumAccess: mutableAccess,
            scanUsageRepository: scanUsageRepository
        )
        revocableViewModel.clusterControls.sort = .similarity
        revocableViewModel.clusterControls.reviewFilter = .reviewed
        revocableViewModel.clusterControls.minimumClusterSize = .twenty
        revocableViewModel.clusterControls.favoritesOnly = true

        XCTAssertEqual(
            revocableViewModel.effectiveClusterControls,
            revocableViewModel.clusterControls
        )

        mutableAccess.unlocksAdvancedFilters = false

        XCTAssertEqual(revocableViewModel.effectiveClusterControls.sort, .similarity)
        XCTAssertEqual(revocableViewModel.effectiveClusterControls.reviewFilter, .all)
        XCTAssertEqual(revocableViewModel.effectiveClusterControls.minimumClusterSize, .any)
        XCTAssertFalse(revocableViewModel.effectiveClusterControls.favoritesOnly)

        let lowSimilarity = PhotoCluster(
            id: UUID(),
            assets: [],
            createdAt: Date(timeIntervalSince1970: 200),
            averageSimilarity: 0.2
        )
        let highSimilarity = PhotoCluster(
            id: UUID(),
            assets: [],
            createdAt: Date(timeIntervalSince1970: 100),
            averageSimilarity: 0.9
        )

        XCTAssertEqual(
            revocableViewModel.sortedClusters(from: [lowSimilarity, highSimilarity]).map(\.id),
            [highSimilarity.id, lowSimilarity.id]
        )
    }
    
    // MARK: - Load Cached Results Tests
    
    func testLoadCachedResultsWithData() async {
        let mockCluster = createMockCluster(photoCount: 2)
        let cleanupRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 2,
            estimatedSavingsBytes: 2_048
        )
        await mockRepository.setLoadClustersResult(.success([mockCluster]))
        await mockCleanupCategoryRepository.setStoredSnapshots([
            .screenshots: CleanupCategorySnapshot(
                kind: .screenshots,
                localIdentifiers: ["s1", "s2", "s3", "s4", "s5"],
                assetCount: 5,
                estimatedSavingsBytes: 500
            )
        ])
        await mockCleanupHistoryRepository.setEntries([cleanupRecord])
        
        await viewModel.loadCachedResults()
        
        if case .results(let clusters) = viewModel.state {
            XCTAssertEqual(clusters.count, 1)
        } else {
            XCTFail("Expected results state")
        }
        XCTAssertEqual(viewModel.cleanupCategories.count, 1)
        XCTAssertEqual(viewModel.cleanupInsights.totalDeletedItems, 2)
        XCTAssertEqual(viewModel.cleanupInsights.totalSavedBytes, 2_048)
    }
    
    func testLoadCachedResultsEmpty() async {
        await mockRepository.setLoadClustersResult(.success([]))
        await viewModel.loadCachedResults()
        
        if case .idle = viewModel.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected idle state")
        }
    }

    func testLoadCachedResultsErrorKeepsIdleState() async {
        await mockRepository.setLoadClustersResult(.failure(TestError()))
        await viewModel.loadCachedResults()

        if case .idle = viewModel.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected idle state after error")
        }
    }

    func testDeniedScanDoesNotSuppressInFlightCachedResults() async {
        let cachedCluster = createMockCluster(photoCount: 2)
        let suspendedRepository = SuspendedCachedLoadPhotoClusterRepository()
        let usageRepository = MockScanUsageRepository(count: 3)
        let cacheAwareViewModel = ScannerViewModel(
            analysisService: mockAnalysisService,
            repository: suspendedRepository,
            reviewRepository: mockReviewRepository,
            cleanupCategoryRepository: mockCleanupCategoryRepository,
            cleanupSessionRepository: mockCleanupSessionRepository,
            cleanupService: mockCleanupService,
            cleanupHistoryRepository: mockCleanupHistoryRepository,
            premiumAccess: premiumAccess,
            scanUsageRepository: usageRepository
        )

        let cacheLoad = Task { await cacheAwareViewModel.loadCachedResults() }
        await suspendedRepository.waitUntilLoadClustersCallCount(1)

        let decision = await cacheAwareViewModel.startScanning()
        await suspendedRepository.resumeNextLoadClusters(returning: [cachedCluster])
        await cacheLoad.value

        XCTAssertEqual(decision, .requiresPremium)
        XCTAssertEqual(cacheAwareViewModel.state, .results([cachedCluster]))
    }

    func testInFlightCachedResultsCannotOverwriteNewerManualScan() async {
        let cachedCluster = createMockCluster(photoCount: 2)
        let scannedCluster = createMockCluster(photoCount: 2)
        let suspendedRepository = SuspendedCachedLoadPhotoClusterRepository()
        let suspendedAnalysis = SuspendedPhotoAnalysisService()
        let cacheAwareViewModel = ScannerViewModel(
            analysisService: suspendedAnalysis,
            repository: suspendedRepository,
            reviewRepository: mockReviewRepository,
            cleanupCategoryRepository: mockCleanupCategoryRepository,
            cleanupSessionRepository: mockCleanupSessionRepository,
            cleanupService: mockCleanupService,
            cleanupHistoryRepository: mockCleanupHistoryRepository,
            premiumAccess: premiumAccess,
            scanUsageRepository: scanUsageRepository,
            premiumPromptHistoryRepository: premiumPromptHistoryRepository
        )

        let cacheLoad = Task { await cacheAwareViewModel.loadCachedResults() }
        await suspendedRepository.waitUntilLoadClustersCallCount(1)
        let manualScan = Task { await cacheAwareViewModel.startScanning() }
        await suspendedAnalysis.waitUntilAnalyzeCallCount(1)
        await suspendedAnalysis.resumeNext(returning: [scannedCluster])
        _ = await manualScan.value

        await suspendedRepository.resumeNextLoadClusters(returning: [cachedCluster])
        await cacheLoad.value

        XCTAssertEqual(cacheAwareViewModel.state, .results([scannedCluster]))
    }

    func testLoadCachedResultsKeepsCanonicalClustersWhenFiltersAreActive() async {
        viewModel = makeViewModel(
            premiumAccess: MockPremiumAccessController(unlockedFeatures: [.advancedFilters])
        )
        let reviewed = createMockCluster(photoCount: 2)
        let notReviewed = createMockCluster(photoCount: 2)
        viewModel.clusterControls.reviewFilter = .reviewed
        await mockRepository.setLoadClustersResult(.success([reviewed, notReviewed]))

        await viewModel.loadCachedResults()

        guard case .results(let clusters) = viewModel.state else {
            return XCTFail("Expected cached results state")
        }
        XCTAssertEqual(Set(clusters.map(\.id)), Set([reviewed.id, notReviewed.id]))
        XCTAssertTrue(viewModel.sortedClusters(from: clusters).isEmpty)

        viewModel.resetClusterControls()
        XCTAssertEqual(viewModel.sortedClusters(from: clusters).count, 2)
    }
    
    // MARK: - Scan Tests
    
    func testScanCallsAnalysisService() async {
        let mockCluster = createMockCluster(photoCount: 3)
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([mockCluster]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))
        
        await viewModel.startScanning()
        
        let didCall = await mockAnalysisService.didCallAnalyzePhotoLibrary
        XCTAssertTrue(didCall)
        
        if case .results(let clusters) = viewModel.state {
            XCTAssertEqual(clusters.count, 1)
        }
    }

    func testScanPublishesProgressWhileAnalysisRemainsSuspended() async {
        let analysisService = SuspendedPhotoAnalysisService()
        let progressViewModel = ScannerViewModel(
            analysisService: analysisService,
            repository: mockRepository,
            reviewRepository: mockReviewRepository,
            cleanupCategoryRepository: mockCleanupCategoryRepository,
            cleanupSessionRepository: mockCleanupSessionRepository,
            cleanupService: mockCleanupService,
            cleanupHistoryRepository: mockCleanupHistoryRepository,
            premiumAccess: premiumAccess,
            scanUsageRepository: scanUsageRepository,
            premiumPromptHistoryRepository: premiumPromptHistoryRepository
        )

        let scan = Task { await progressViewModel.startScanning() }
        await analysisService.waitUntilAnalyzeCallCount(1)

        guard case .scanning(let initialProgress) = progressViewModel.state else {
            return XCTFail("Expected scanning state while analysis is suspended")
        }
        XCTAssertEqual(initialProgress, 0)
        let initialReactionID = progressViewModel.currentALIReaction?.id
        XCTAssertEqual(progressViewModel.currentALIReaction?.state, .scanning)

        await analysisService.publishProgress(0.42)
        let progressUpdated = expectation(description: "Scanner publishes analysis progress")
        let progressObserver = Task { @MainActor in
            while !Task.isCancelled {
                if progressViewModel.state == .scanning(progress: 0.42) {
                    progressUpdated.fulfill()
                    return
                }
                await Task.yield()
            }
        }
        await fulfillment(of: [progressUpdated], timeout: 1.0)
        progressObserver.cancel()

        guard case .scanning(let updatedProgress) = progressViewModel.state else {
            return XCTFail("Expected progress update to preserve scanning state")
        }
        XCTAssertEqual(updatedProgress, 0.42)
        XCTAssertEqual(progressViewModel.currentALIReaction?.id, initialReactionID)

        await analysisService.resumeNext(returning: [])
        _ = await scan.value
        XCTAssertEqual(progressViewModel.state, .results([]))
        XCTAssertEqual(progressViewModel.currentALIReaction?.state, .noResults)
    }
    
    func testScanSavesClusters() async {
        let mockCluster = createMockCluster(photoCount: 2)
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([mockCluster]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))
        
        await viewModel.startScanning()
        
        let didCall = await mockRepository.didCallSaveClusters
        XCTAssertTrue(didCall)
        
        let saved = await mockRepository.savedClusters
        XCTAssertEqual(saved.count, 1)
    }

    func testStartScanningCreatesNewCleanupSession() async {
        let mockCluster = createMockCluster(photoCount: 2)
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([mockCluster]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))

        await viewModel.startScanning()

        let session = await mockCleanupSessionRepository.storedSession
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.totalClusters, 1)
        XCTAssertEqual(session?.reviewedClusters, 0)
        XCTAssertEqual(session?.estimatedSavingsBytes, 0)
    }

    func testScanFailureSetsErrorState() async {
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.failure(TestError()))

        await viewModel.startScanning()

        if case .error(let message) = viewModel.state {
            XCTAssertEqual(message, "Test error")
        } else {
            XCTFail("Expected error state")
        }
    }

    func testRescanKeepsCanonicalClustersWhenFiltersAreActive() async {
        viewModel = makeViewModel(
            premiumAccess: MockPremiumAccessController(unlockedFeatures: [.advancedFilters])
        )
        let reviewed = createMockCluster(photoCount: 2)
        let notReviewed = createMockCluster(photoCount: 2)
        viewModel.clusterControls.reviewFilter = .reviewed
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([reviewed, notReviewed]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))

        await viewModel.startScanning()

        guard case .results(let clusters) = viewModel.state else {
            return XCTFail("Expected scan results state")
        }
        XCTAssertEqual(Set(clusters.map(\.id)), Set([reviewed.id, notReviewed.id]))
        XCTAssertTrue(viewModel.sortedClusters(from: clusters).isEmpty)

        viewModel.resetClusterControls()
        XCTAssertEqual(viewModel.sortedClusters(from: clusters).count, 2)
    }

    func testRescanWithActiveFilterPreservesHiddenReviewStates() async {
        let now = Date()
        let reviewedID = UUID()
        let inReviewID = UUID()
        let reviewed = PhotoCluster(id: reviewedID, assets: [], createdAt: now.addingTimeInterval(1))
        let inReview = PhotoCluster(id: inReviewID, assets: [], createdAt: now)
        let reviewedState = ClusterReviewState(
            clusterID: reviewedID,
            bestShotLocalIdentifier: "best-reviewed",
            selectedLocalIdentifiers: ["candidate-reviewed"],
            mode: .selection,
            status: .reviewed,
            estimatedSavingsBytes: 200
        )
        let inReviewState = ClusterReviewState(
            clusterID: inReviewID,
            bestShotLocalIdentifier: "best-in-review",
            selectedLocalIdentifiers: ["candidate-in-review"],
            mode: .selection,
            status: .inReview,
            estimatedSavingsBytes: 100
        )
        viewModel.state = .results([reviewed, inReview])
        await mockRepository.setLoadClusterSnapshotsResult(.success([
            makeSnapshot(id: reviewedID, assets: []),
            makeSnapshot(id: inReviewID, assets: [])
        ]))
        await mockReviewRepository.setStoredStates([
            reviewedID: reviewedState,
            inReviewID: inReviewState
        ])
        await viewModel.loadReviewStates()
        viewModel.clusterControls.reviewFilter = .reviewed
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([reviewed, inReview]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))

        await viewModel.startScanning()

        guard case .results(let clusters) = viewModel.state else {
            return XCTFail("Expected scan results state")
        }
        let storedStates = await mockReviewRepository.storedStates
        XCTAssertEqual(Set(clusters.map(\.id)), Set([reviewedID, inReviewID]))
        XCTAssertEqual(storedStates[reviewedID]?.status, .reviewed)
        XCTAssertEqual(storedStates[inReviewID]?.status, .inReview)
        XCTAssertEqual(storedStates[inReviewID]?.selectedLocalIdentifiers, ["candidate-in-review"])
    }

    func testCheckForGalleryChangesUsesRepository() async {
        let cluster = createMockCluster(photoCount: 2)
        viewModel.state = .results([cluster])
        await mockRepository.setHasGalleryChangedResult(true)
        let hasChanged = await viewModel.checkForGalleryChanges()
        let didCall = await mockRepository.didCallHasGalleryChanged
        XCTAssertTrue(hasChanged)
        XCTAssertTrue(didCall)
        XCTAssertTrue(viewModel.shouldShowRescanPrompt)
    }

    func testCheckForGalleryChangesDoesNotShowPromptWithoutResults() async {
        await mockRepository.setHasGalleryChangedResult(true)

        let hasChanged = await viewModel.checkForGalleryChanges()

        XCTAssertFalse(hasChanged)
        XCTAssertFalse(viewModel.shouldShowRescanPrompt)
    }

    func testSortedClustersOrdersByDateSimilarityAndId() {
        let now = Date()
        let later = now.addingTimeInterval(10)
        let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let id3 = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

        let clusterLate = PhotoCluster(id: id3, assets: [], createdAt: later, averageSimilarity: 0.1)
        let clusterHighSim = PhotoCluster(id: id2, assets: [], createdAt: now, averageSimilarity: 0.9)
        let clusterLowSim = PhotoCluster(id: id1, assets: [], createdAt: now, averageSimilarity: 0.8)

        let sorted = viewModel.sortedClusters(from: [clusterLowSim, clusterHighSim, clusterLate])

        XCTAssertEqual(sorted.first?.id, id3, "Newest cluster should come first")
        XCTAssertEqual(sorted[1].id, id2, "Higher similarity should come before lower similarity")
        XCTAssertEqual(sorted[2].id, id1, "Lower similarity should come last")
    }

    func testReviewStatusReturnsStoredStatus() async throws {
        let clusterID = UUID()
        await mockReviewRepository.setStoredStates([
            clusterID: ClusterReviewState(
                clusterID: clusterID,
                bestShotLocalIdentifier: "best",
                selectedLocalIdentifiers: ["candidate"],
                mode: .selection,
                status: .inReview,
                estimatedSavingsBytes: 100
            )
        ])

        await viewModel.loadReviewStates()

        XCTAssertEqual(viewModel.reviewStatus(for: clusterID), .inReview)
    }

    func testUnknownReviewStatusDefaultsToNotReviewed() async {
        await viewModel.loadReviewStates()
        XCTAssertEqual(viewModel.reviewStatus(for: UUID()), .notReviewed)
    }

    func testSessionProgressAggregatesMixedStatuses() async {
        let reviewedID = UUID()
        let needsReviewID = UUID()
        let inReviewID = UUID()
        let notReviewedID = UUID()
        let unknownStateID = UUID()

        let clusters = [
            createMockCluster(id: reviewedID, photoCount: 3),
            createMockCluster(id: needsReviewID, photoCount: 3),
            createMockCluster(id: inReviewID, photoCount: 3),
            createMockCluster(id: notReviewedID, photoCount: 3)
        ]

        await mockReviewRepository.setStoredStates([
            reviewedID: ClusterReviewState(
                clusterID: reviewedID,
                bestShotLocalIdentifier: "best-1",
                selectedLocalIdentifiers: ["a", "b"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 1_000
            ),
            needsReviewID: ClusterReviewState(
                clusterID: needsReviewID,
                bestShotLocalIdentifier: "best-0",
                selectedLocalIdentifiers: ["stale"],
                mode: .selection,
                status: .needsReReview,
                estimatedSavingsBytes: 10_000,
                resurfacingState: .changed
            ),
            inReviewID: ClusterReviewState(
                clusterID: inReviewID,
                bestShotLocalIdentifier: "best-2",
                selectedLocalIdentifiers: ["a"],
                mode: .selection,
                status: .inReview,
                estimatedSavingsBytes: 2_000
            ),
            unknownStateID: ClusterReviewState(
                clusterID: unknownStateID,
                bestShotLocalIdentifier: "best-3",
                selectedLocalIdentifiers: ["a"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 9_999
            )
        ])

        await viewModel.loadReviewStates()
        let progress = viewModel.sessionProgress(for: clusters)

        XCTAssertEqual(progress.totalClusters, 4)
        XCTAssertEqual(progress.reviewedCount, 1)
        XCTAssertEqual(progress.needsReReviewCount, 1)
        XCTAssertEqual(progress.inReviewCount, 1)
        XCTAssertEqual(progress.notReviewedCount, 1)
        XCTAssertEqual(progress.reviewedSavingsBytes, 3_000)
        XCTAssertEqual(progress.totalSelectedItems, 3)
        XCTAssertEqual(progress.remainingClusters, 3)
    }

    func testGlobalSessionProgressAndContinueCandidateIgnoreVisibleFilters() async {
        viewModel = makeViewModel(
            premiumAccess: MockPremiumAccessController(unlockedFeatures: [.advancedFilters])
        )
        let reviewedID = UUID()
        let notReviewedID = UUID()
        let reviewed = createMockCluster(id: reviewedID, photoCount: 2)
        let notReviewed = createMockCluster(id: notReviewedID, photoCount: 2)
        let clusters = [reviewed, notReviewed]
        await mockReviewRepository.setStoredStates([
            reviewedID: ClusterReviewState(
                clusterID: reviewedID,
                bestShotLocalIdentifier: "best",
                selectedLocalIdentifiers: ["candidate"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 100
            )
        ])
        viewModel.state = .results(clusters)
        await viewModel.loadReviewStates()
        viewModel.clusterControls.reviewFilter = .reviewed

        let canonical = viewModel.canonicalSortedClusters(from: clusters)
        let visible = viewModel.sortedClusters(from: canonical)
        let progress = viewModel.displayedSessionProgress(for: canonical)

        XCTAssertEqual(visible.map(\.id), [reviewedID])
        XCTAssertEqual(progress.totalClusters, 2)
        XCTAssertEqual(progress.reviewedCount, 1)
        XCTAssertEqual(progress.remainingClusters, 1)
        XCTAssertEqual(viewModel.cleanupEntryCluster(from: canonical)?.id, notReviewedID)
    }

    func testSessionProgressPercentZeroForNoClusters() {
        let progress = viewModel.sessionProgress(for: [])
        XCTAssertEqual(progress.reviewedRatio, 0)
        XCTAssertEqual(progress.reviewedPercent, 0)
    }

    func testSessionProgressPercentForPartialAndFullCompletion() async {
        let firstID = UUID()
        let secondID = UUID()
        let clusters = [
            createMockCluster(id: firstID, photoCount: 2),
            createMockCluster(id: secondID, photoCount: 2)
        ]

        await mockReviewRepository.setStoredStates([
            firstID: ClusterReviewState(
                clusterID: firstID,
                bestShotLocalIdentifier: "best",
                selectedLocalIdentifiers: ["a"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 111
            )
        ])
        await viewModel.loadReviewStates()

        let partial = viewModel.sessionProgress(for: clusters)
        XCTAssertEqual(partial.reviewedCount, 1)
        XCTAssertEqual(partial.reviewedPercent, 50)

        await mockReviewRepository.setStoredStates([
            firstID: ClusterReviewState(
                clusterID: firstID,
                bestShotLocalIdentifier: "best-1",
                selectedLocalIdentifiers: ["a"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 111
            ),
            secondID: ClusterReviewState(
                clusterID: secondID,
                bestShotLocalIdentifier: "best-2",
                selectedLocalIdentifiers: ["b"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 222
            )
        ])
        await viewModel.loadReviewStates()

        let full = viewModel.sessionProgress(for: clusters)
        XCTAssertEqual(full.reviewedCount, 2)
        XCTAssertEqual(full.reviewedPercent, 100)
        XCTAssertEqual(full.remainingClusters, 0)
    }

    func testLoadCachedResultsIncludesPersistedStatesForSessionProgress() async {
        let clusterID = UUID()
        let cluster = createMockCluster(id: clusterID, photoCount: 3)
        await mockRepository.setLoadClustersResult(.success([cluster]))
        await mockReviewRepository.setStoredStates([
            clusterID: ClusterReviewState(
                clusterID: clusterID,
                bestShotLocalIdentifier: "best",
                selectedLocalIdentifiers: ["a", "b"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 2_048
            )
        ])

        await viewModel.loadCachedResults()

        if case .results(let clusters) = viewModel.state {
            let progress = viewModel.sessionProgress(for: clusters)
            XCTAssertEqual(progress.totalClusters, 1)
            XCTAssertEqual(progress.reviewedCount, 1)
            XCTAssertEqual(progress.reviewedPercent, 100)
            XCTAssertEqual(progress.reviewedSavingsBytes, 2_048)
        } else {
            XCTFail("Expected results state")
        }
    }

    func testLoadCachedResultsRestoresExistingCleanupSession() async {
        let cluster = createMockCluster(photoCount: 2)
        let existingSession = CleanupSession(
            totalClusters: 1,
            reviewedClusters: 0,
            estimatedSavingsBytes: 0
        )
        await mockRepository.setLoadClustersResult(.success([cluster]))
        await mockCleanupSessionRepository.setStoredSession(existingSession)

        await viewModel.loadCachedResults()

        XCTAssertEqual(viewModel.activeCleanupSession?.id, existingSession.id)
        XCTAssertEqual(viewModel.activeCleanupSession?.totalClusters, 1)
    }

    func testLoadReviewStatesUpdatesCleanupSessionAggregates() async {
        let reviewedID = UUID()
        let needsReviewID = UUID()
        let inReviewID = UUID()
        let clusters = [
            createMockCluster(id: reviewedID, photoCount: 2),
            createMockCluster(id: needsReviewID, photoCount: 2),
            createMockCluster(id: inReviewID, photoCount: 2)
        ]
        let existingSession = CleanupSession(
            totalClusters: 3,
            reviewedClusters: 0,
            estimatedSavingsBytes: 0
        )
        await mockCleanupSessionRepository.setStoredSession(existingSession)
        await mockReviewRepository.setStoredStates([
            reviewedID: ClusterReviewState(
                clusterID: reviewedID,
                bestShotLocalIdentifier: "best-1",
                selectedLocalIdentifiers: ["a"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 1_000
            ),
            needsReviewID: ClusterReviewState(
                clusterID: needsReviewID,
                bestShotLocalIdentifier: "best-0",
                selectedLocalIdentifiers: [],
                mode: .selection,
                status: .needsReReview,
                estimatedSavingsBytes: 0,
                resurfacingState: .new
            ),
            inReviewID: ClusterReviewState(
                clusterID: inReviewID,
                bestShotLocalIdentifier: "best-2",
                selectedLocalIdentifiers: ["a"],
                mode: .selection,
                status: .inReview,
                estimatedSavingsBytes: 2_000
            )
        ])

        viewModel.state = .results(clusters)
        await viewModel.loadReviewStates()

        let session = viewModel.activeCleanupSession
        XCTAssertEqual(session?.id, existingSession.id)
        XCTAssertEqual(session?.reviewedClusters, 1)
        XCTAssertEqual(session?.estimatedSavingsBytes, 3_000)
    }

    func testLoadReviewStatesSeparatesNeedsReviewClustersFromRemainingClusters() async {
        let needsReviewID = UUID()
        let reviewedID = UUID()
        let clusters = [
            createMockCluster(id: needsReviewID, photoCount: 2),
            createMockCluster(id: reviewedID, photoCount: 2)
        ]
        await mockReviewRepository.setStoredStates([
            needsReviewID: ClusterReviewState(
                clusterID: needsReviewID,
                bestShotLocalIdentifier: "best-0",
                selectedLocalIdentifiers: [],
                mode: .selection,
                status: .needsReReview,
                estimatedSavingsBytes: 0,
                resurfacingState: .changed
            ),
            reviewedID: ClusterReviewState(
                clusterID: reviewedID,
                bestShotLocalIdentifier: "best-1",
                selectedLocalIdentifiers: ["a"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 100
            )
        ])

        viewModel.state = .results(clusters)
        await viewModel.loadReviewStates()

        XCTAssertEqual(viewModel.needsReviewClusters(from: clusters).map(\.id), [needsReviewID])
        XCTAssertEqual(viewModel.remainingClusters(from: clusters).map(\.id), [reviewedID])
        XCTAssertEqual(viewModel.resurfacingState(for: needsReviewID), .changed)
    }

    func testStartScanningClearsRescanPromptAfterSuccessfulScan() async {
        let cluster = createMockCluster(photoCount: 2)
        viewModel.state = .results([cluster])
        await mockRepository.setHasGalleryChangedResult(true)
        _ = await viewModel.checkForGalleryChanges()
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([cluster]))

        await viewModel.startScanning()

        XCTAssertFalse(viewModel.shouldShowRescanPrompt)
    }

    func testResurfacerPreservesExactMatchState() {
        let oldID = UUID()
        let newID = UUID()
        let oldSnapshot = makeSnapshot(id: oldID, assets: ["a", "b"], favoriteIDs: ["a"])
        let newSnapshot = makeSnapshot(id: newID, assets: ["a", "b"], favoriteIDs: ["a"])
        let oldState = ClusterReviewState(
            clusterID: oldID,
            bestShotLocalIdentifier: "a",
            selectedLocalIdentifiers: ["b"],
            mode: .selection,
            status: .reviewed,
            estimatedSavingsBytes: 100
        )

        let result = ClusterReviewStateResurfacer.resurface(
            previousSnapshots: [oldSnapshot],
            newSnapshots: [newSnapshot],
            existingReviewStates: [oldID: oldState]
        )

        XCTAssertEqual(result.resurfacingStates[newID], .unchanged)
        XCTAssertEqual(result.migratedReviewStates[newID]?.status, .reviewed)
        XCTAssertEqual(result.migratedReviewStates[newID]?.selectedLocalIdentifiers, ["b"])
    }

    func testResurfacerMarksAddedAssetClusterAsChanged() {
        let oldID = UUID()
        let newID = UUID()
        let oldSnapshot = makeSnapshot(id: oldID, assets: ["a", "b"], favoriteIDs: ["a"])
        let newSnapshot = makeSnapshot(id: newID, assets: ["a", "b", "c"], favoriteIDs: ["a"])

        let result = ClusterReviewStateResurfacer.resurface(
            previousSnapshots: [oldSnapshot],
            newSnapshots: [newSnapshot],
            existingReviewStates: [:]
        )

        XCTAssertEqual(result.resurfacingStates[newID], .changed)
        XCTAssertEqual(result.migratedReviewStates[newID]?.status, .needsReReview)
        XCTAssertEqual(result.migratedReviewStates[newID]?.resurfacingState, .changed)
    }

    func testResurfacerMarksDeletedAssetClusterAsChanged() {
        let oldID = UUID()
        let newID = UUID()
        let oldSnapshot = makeSnapshot(id: oldID, assets: ["a", "b", "c"], favoriteIDs: ["a"])
        let newSnapshot = makeSnapshot(id: newID, assets: ["a", "b"], favoriteIDs: ["a"])

        let result = ClusterReviewStateResurfacer.resurface(
            previousSnapshots: [oldSnapshot],
            newSnapshots: [newSnapshot],
            existingReviewStates: [:]
        )

        XCTAssertEqual(result.resurfacingStates[newID], .changed)
        XCTAssertEqual(result.migratedReviewStates[newID]?.status, .needsReReview)
    }

    func testResurfacerMarksBestShotChangeAsChanged() {
        let oldID = UUID()
        let newID = UUID()
        let oldSnapshot = makeSnapshot(id: oldID, assets: ["a", "b"], favoriteIDs: ["a"])
        let newSnapshot = makeSnapshot(id: newID, assets: ["a", "b"], favoriteIDs: ["b"])

        let result = ClusterReviewStateResurfacer.resurface(
            previousSnapshots: [oldSnapshot],
            newSnapshots: [newSnapshot],
            existingReviewStates: [:]
        )

        XCTAssertEqual(result.resurfacingStates[newID], .changed)
        XCTAssertEqual(result.migratedReviewStates[newID]?.bestShotLocalIdentifier, "b")
    }

    func testResurfacerMarksBrandNewClusterAsNew() {
        let oldSnapshot = makeSnapshot(id: UUID(), assets: ["a", "b"], favoriteIDs: ["a"])
        let newID = UUID()
        let newSnapshot = makeSnapshot(id: newID, assets: ["x", "y"], favoriteIDs: ["x"])

        let result = ClusterReviewStateResurfacer.resurface(
            previousSnapshots: [oldSnapshot],
            newSnapshots: [newSnapshot],
            existingReviewStates: [:]
        )

        XCTAssertEqual(result.resurfacingStates[newID], .new)
        XCTAssertEqual(result.migratedReviewStates[newID]?.status, .needsReReview)
        XCTAssertEqual(result.migratedReviewStates[newID]?.resurfacingState, .new)
    }

    func testSessionUpdateIgnoresOrphanReviewStates() async {
        let clusterID = UUID()
        let orphanID = UUID()
        let clusters = [createMockCluster(id: clusterID, photoCount: 2)]
        await mockReviewRepository.setStoredStates([
            clusterID: ClusterReviewState(
                clusterID: clusterID,
                bestShotLocalIdentifier: "best",
                selectedLocalIdentifiers: ["a"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 111
            ),
            orphanID: ClusterReviewState(
                clusterID: orphanID,
                bestShotLocalIdentifier: "orphan",
                selectedLocalIdentifiers: ["b"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 9_999
            )
        ])

        viewModel.state = .results(clusters)
        await viewModel.loadReviewStates()

        let session = viewModel.activeCleanupSession
        XCTAssertEqual(session?.totalClusters, 1)
        XCTAssertEqual(session?.reviewedClusters, 1)
        XCTAssertEqual(session?.estimatedSavingsBytes, 111)

        let progress = viewModel.sessionProgress(for: clusters)
        XCTAssertEqual(progress.totalSelectedItems, 1)
    }

    func testLoadCachedResultsEmptyClearsCleanupSession() async {
        let existingSession = CleanupSession(
            totalClusters: 2,
            reviewedClusters: 1,
            estimatedSavingsBytes: 123
        )
        await mockRepository.setLoadClustersResult(.success([]))
        await mockCleanupSessionRepository.setStoredSession(existingSession)

        await viewModel.loadCachedResults()

        XCTAssertNil(viewModel.activeCleanupSession)
        let stored = await mockCleanupSessionRepository.storedSession
        XCTAssertNil(stored)
    }

    func testCleanupEntryClusterPrefersNotReviewedThenInReviewAndStopsWhenReviewed() async {
        let notReviewedID = UUID()
        let inReviewID = UUID()
        let reviewedID = UUID()

        let notReviewed = createMockCluster(id: notReviewedID, photoCount: 2)
        let inReview = createMockCluster(id: inReviewID, photoCount: 2)
        let reviewed = createMockCluster(id: reviewedID, photoCount: 2)

        await mockReviewRepository.setStoredStates([
            inReviewID: ClusterReviewState(
                clusterID: inReviewID,
                bestShotLocalIdentifier: "best-1",
                selectedLocalIdentifiers: ["a"],
                mode: .selection,
                status: .inReview,
                estimatedSavingsBytes: 10
            ),
            reviewedID: ClusterReviewState(
                clusterID: reviewedID,
                bestShotLocalIdentifier: "best-2",
                selectedLocalIdentifiers: ["a"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 20
            )
        ])
        await viewModel.loadReviewStates()

        let clusters = [reviewed, inReview, notReviewed]
        XCTAssertEqual(viewModel.cleanupEntryCluster(from: clusters)?.id, notReviewedID)

        let noNotReviewed = [reviewed, inReview]
        XCTAssertEqual(viewModel.cleanupEntryCluster(from: noNotReviewed)?.id, inReviewID)

        XCTAssertNil(viewModel.cleanupEntryCluster(from: [reviewed]))
    }

    func testHandleCleanupCompletedReviewStateLoadFailureDoesNotMutatePersistedState() async throws {
        let oldCluster = createMockCluster(photoCount: 2)
        let unrelatedClusterID = UUID()
        let unrelatedState = ClusterReviewState(
            clusterID: unrelatedClusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: ["candidate"],
            mode: .selection,
            status: .reviewed,
            estimatedSavingsBytes: 400
        )
        let completionRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 1,
            estimatedSavingsBytes: 512
        )
        viewModel.state = .results([oldCluster])
        await mockRepository.setLoadClusterSnapshotsResult(.success([
            makeSnapshot(id: oldCluster.id, assets: [])
        ]))
        await mockReviewRepository.setStoredStates([unrelatedClusterID: unrelatedState])
        await mockReviewRepository.setLoadAllReviewStatesError(TestError())

        await viewModel.handleCleanupCompleted(completionRecord)

        let persistedState = try await mockReviewRepository.loadReviewState(
            clusterID: unrelatedClusterID
        )
        let didDeleteReviewStates = await mockReviewRepository.didCallDeleteAllReviewStates
        let didSaveClusters = await mockRepository.didCallSaveClusters
        XCTAssertEqual(persistedState, unrelatedState)
        XCTAssertFalse(didDeleteReviewStates)
        XCTAssertFalse(didSaveClusters)
        XCTAssertEqual(viewModel.state, .results([oldCluster]))
        guard case .failed(let record, _) = viewModel.cleanupRefreshState else {
            return XCTFail("Expected failed cleanup refresh state")
        }
        XCTAssertEqual(record, completionRecord)
    }

    func testHandleCleanupCompletedSerializesAndCoalescesRefreshes() async {
        let analysisService = SuspendedPhotoAnalysisService()
        let serializedViewModel = ScannerViewModel(
            gridColumns: 3,
            sensitivity: .medium,
            analysisService: analysisService,
            repository: mockRepository,
            reviewRepository: mockReviewRepository,
            cleanupCategoryRepository: mockCleanupCategoryRepository,
            cleanupSessionRepository: mockCleanupSessionRepository,
            cleanupService: mockCleanupService,
            cleanupHistoryRepository: mockCleanupHistoryRepository,
            premiumAccess: premiumAccess
        )
        let firstCluster = createMockCluster(photoCount: 2)
        let secondCluster = createMockCluster(photoCount: 2)
        let firstRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 1,
            estimatedSavingsBytes: 100
        )
        let secondRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 2,
            estimatedSavingsBytes: 200
        )

        let firstTask = Task {
            await serializedViewModel.handleCleanupCompleted(firstRecord)
        }
        await analysisService.waitUntilAnalyzeCallCount(1)
        XCTAssertTrue(serializedViewModel.isCleanupRefreshInProgress)

        let duplicateTask = Task {
            await serializedViewModel.handleCleanupCompleted(firstRecord)
        }
        let secondTask = Task {
            await serializedViewModel.handleCleanupCompleted(secondRecord)
        }
        await duplicateTask.value
        await secondTask.value
        var analyzeCallCount = await analysisService.currentAnalyzeCallCount()
        var maximumConcurrentCount = await analysisService.maximumConcurrentAnalyzeCount()
        XCTAssertEqual(analyzeCallCount, 1)
        XCTAssertEqual(maximumConcurrentCount, 1)

        await analysisService.resumeNext(returning: [firstCluster])
        await analysisService.waitUntilAnalyzeCallCount(2)
        maximumConcurrentCount = await analysisService.maximumConcurrentAnalyzeCount()
        XCTAssertEqual(maximumConcurrentCount, 1)
        await analysisService.resumeNext(returning: [secondCluster])
        await firstTask.value

        analyzeCallCount = await analysisService.currentAnalyzeCallCount()
        maximumConcurrentCount = await analysisService.maximumConcurrentAnalyzeCount()
        XCTAssertEqual(analyzeCallCount, 2)
        XCTAssertEqual(maximumConcurrentCount, 1)
        XCTAssertFalse(serializedViewModel.isCleanupRefreshInProgress)
        XCTAssertEqual(serializedViewModel.state, .results([secondCluster]))
        XCTAssertEqual(serializedViewModel.cleanupRefreshState, .success(secondRecord))
    }

    func testHandleCleanupCompletedPreservesUnrelatedReviewStateAndRefreshesResults() async throws {
        let clusterID = UUID()
        let cluster = createMockCluster(id: clusterID, photoCount: 2)
        let completionRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 2,
            estimatedSavingsBytes: 1_024
        )
        let existingReviewState = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: ["candidate"],
            mode: .selection,
            status: .reviewed,
            estimatedSavingsBytes: 400
        )
        viewModel.state = .results([cluster])
        await mockRepository.setLoadClusterSnapshotsResult(.success([
            makeSnapshot(id: clusterID, assets: [])
        ]))
        await mockReviewRepository.setStoredStates([clusterID: existingReviewState])
        await viewModel.loadReviewStates()
        let existingSessionID = viewModel.activeCleanupSession?.id
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([cluster]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([
            CleanupCategorySummary(kind: .screenshots, assetCount: 3, estimatedSavingsBytes: 300)
        ]))
        await mockCleanupHistoryRepository.setEntries([completionRecord])

        await viewModel.handleCleanupCompleted(completionRecord)

        let didDeleteClusters = await mockRepository.didCallDeleteAllClusters
        let didDeleteSession = await mockCleanupSessionRepository.didCallDeleteActiveSession
        let preservedReviewState = try await mockReviewRepository.loadReviewState(clusterID: clusterID)

        XCTAssertFalse(didDeleteClusters)
        XCTAssertFalse(didDeleteSession)
        XCTAssertEqual(preservedReviewState?.status, .reviewed)
        XCTAssertEqual(preservedReviewState?.selectedLocalIdentifiers, ["candidate"])
        XCTAssertEqual(viewModel.activeCleanupSession?.id, existingSessionID)
        XCTAssertEqual(viewModel.activeCleanupSession?.reviewedClusters, 1)

        if case .results(let clusters) = viewModel.state {
            XCTAssertEqual(clusters.count, 1)
        } else {
            XCTFail("Expected refreshed results state")
        }

        XCTAssertEqual(viewModel.cleanupRefreshState, .success(completionRecord))
        XCTAssertEqual(
            viewModel.currentALIReaction?.state,
            .cleanupSuccess(ALICleanupSummary(itemCount: 2, estimatedSavingsBytes: 1_024))
        )
        XCTAssertEqual(
            viewModel.currentALIReaction?.id.eventID,
            .cleanup(completionRecord.id)
        )
        XCTAssertEqual(viewModel.cleanupCategories.first?.assetCount, 3)
        XCTAssertEqual(viewModel.cleanupInsights.totalDeletedItems, 2)
        XCTAssertEqual(viewModel.cleanupInsights.totalSavedBytes, 1_024)
    }

    func testIsCategoryLockedUsesPremiumAccess() {
        XCTAssertTrue(viewModel.isCategoryLocked(.screenshots))
        XCTAssertTrue(viewModel.isCategoryLocked(.blurredPhotos))

        let unlockedViewModel = ScannerViewModel(
            gridColumns: 3,
            sensitivity: .medium,
            analysisService: mockAnalysisService,
            repository: mockRepository,
            reviewRepository: mockReviewRepository,
            cleanupCategoryRepository: mockCleanupCategoryRepository,
            cleanupSessionRepository: mockCleanupSessionRepository,
            cleanupService: mockCleanupService,
            cleanupHistoryRepository: mockCleanupHistoryRepository,
            premiumAccess: MockPremiumAccessController(unlockedFeatures: [.screenshotCleanup, .blurredPhotoCleanup])
        )

        XCTAssertFalse(unlockedViewModel.isCategoryLocked(.screenshots))
        XCTAssertFalse(unlockedViewModel.isCategoryLocked(.blurredPhotos))
    }

    func testLoadCachedResultsKeepsCategoryOrderingStable() async {
        let mockCluster = createMockCluster(photoCount: 2)
        await mockRepository.setLoadClustersResult(.success([mockCluster]))
        await mockCleanupCategoryRepository.setStoredSnapshots([
            .blurredPhotos: CleanupCategorySnapshot(
                kind: .blurredPhotos,
                localIdentifiers: ["b1"],
                assetCount: 1,
                estimatedSavingsBytes: 200
            ),
            .screenshots: CleanupCategorySnapshot(
                kind: .screenshots,
                localIdentifiers: ["s1"],
                assetCount: 1,
                estimatedSavingsBytes: 100
            )
        ])

        await viewModel.loadCachedResults()

        XCTAssertEqual(viewModel.cleanupCategories.map(\.kind), [.screenshots, .blurredPhotos])
    }

    func testHandleCleanupCompletedFailureKeepsSafeResultsAndCanRetry() async {
        let oldCluster = createMockCluster(photoCount: 2)
        let refreshedCluster = createMockCluster(photoCount: 2)
        let completionRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 1,
            estimatedSavingsBytes: 512
        )
        viewModel.state = .results([oldCluster])
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.failure(TestError()))
        await mockCleanupHistoryRepository.setEntries([completionRecord])

        await viewModel.handleCleanupCompleted(completionRecord)

        if case .results(let clusters) = viewModel.state {
            XCTAssertEqual(clusters.map(\.id), [oldCluster.id])
        } else {
            XCTFail("Expected previous results after failed cleanup refresh")
        }

        switch viewModel.cleanupRefreshState {
        case .failed(let record, let message):
            XCTAssertEqual(record, completionRecord)
            XCTAssertFalse(message.isEmpty)
        default:
            XCTFail("Expected failed cleanup refresh state")
        }
        XCTAssertEqual(
            viewModel.currentALIReaction?.state,
            .recoverableError(ALIErrorContext(operation: .reconciliation))
        )

        let didDeleteClusters = await mockRepository.didCallDeleteAllClusters
        XCTAssertFalse(didDeleteClusters)
        XCTAssertEqual(viewModel.cleanupInsights.totalDeletedItems, 1)
        XCTAssertEqual(viewModel.cleanupInsights.totalSavedBytes, 512)

        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([refreshedCluster]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))
        await viewModel.retryCleanupRefresh()

        if case .results(let clusters) = viewModel.state {
            XCTAssertEqual(clusters.map(\.id), [refreshedCluster.id])
        } else {
            XCTFail("Expected refreshed results after retry")
        }
        XCTAssertEqual(viewModel.cleanupRefreshState, .success(completionRecord))
        XCTAssertEqual(
            viewModel.currentALIReaction?.state,
            .cleanupSuccess(ALICleanupSummary(itemCount: 1, estimatedSavingsBytes: 512))
        )
    }

    func testHandleCleanupCompletedSuccessAutoDismissesBannerAfterDelay() async {
        let cluster = createMockCluster(photoCount: 2)
        let completionRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 2,
            estimatedSavingsBytes: 1_024
        )
        let fastViewModel = ScannerViewModel(
            gridColumns: 3,
            sensitivity: .medium,
            analysisService: mockAnalysisService,
            repository: mockRepository,
            reviewRepository: mockReviewRepository,
            cleanupCategoryRepository: mockCleanupCategoryRepository,
            cleanupSessionRepository: mockCleanupSessionRepository,
            cleanupService: mockCleanupService,
            cleanupHistoryRepository: mockCleanupHistoryRepository,
            premiumAccess: premiumAccess,
            cleanupRefreshAutoDismissDelay: .zero
        )
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([cluster]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))
        await mockCleanupHistoryRepository.setEntries([completionRecord])

        await fastViewModel.handleCleanupCompleted(completionRecord)
        await Task.yield()

        XCTAssertNil(fastViewModel.cleanupRefreshState)
    }

    func testCleanupInsightsFailureSuppressesCleanupSuccess() async {
        let record = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 1,
            estimatedSavingsBytes: 256
        )
        let failingViewModel = ScannerViewModel(
            analysisService: mockAnalysisService,
            repository: mockRepository,
            reviewRepository: mockReviewRepository,
            cleanupCategoryRepository: mockCleanupCategoryRepository,
            cleanupSessionRepository: mockCleanupSessionRepository,
            cleanupService: mockCleanupService,
            cleanupHistoryRepository: mockCleanupHistoryRepository,
            premiumAccess: premiumAccess,
            scanUsageRepository: scanUsageRepository,
            premiumPromptHistoryRepository: premiumPromptHistoryRepository,
            cleanupInsightsProvider: FailingCleanupInsightsProvider()
        )
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([]))

        await failingViewModel.handleCleanupCompleted(record)

        guard case .failed(let failedRecord, _)? = failingViewModel.cleanupRefreshState else {
            return XCTFail("Expected failed cleanup refresh when insights cannot reload")
        }
        XCTAssertEqual(failedRecord, record)
        XCTAssertEqual(
            failingViewModel.currentALIReaction?.state,
            .recoverableError(ALIErrorContext(operation: .reconciliation))
        )
    }
    
    // MARK: - Clear Results Tests
    
    func testClearResults() {
        let cluster = createMockCluster(photoCount: 3)
        viewModel.state = .results([cluster])
        
        viewModel.state = .idle
        
        if case .idle = viewModel.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected idle state")
        }
    }
    
    // MARK: - Helper

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeMonthlyUsage(count: Int, date: Date) -> MonthlyScanUsage {
        let calendar = utcCalendar
        let components = calendar.dateComponents([.year, .month], from: date)
        let periodStart = calendar.date(from: components)!
        return MonthlyScanUsage(
            periodStart: periodStart,
            nextResetDate: calendar.date(byAdding: .month, value: 1, to: periodStart)!,
            completedScanCount: count
        )
    }

    private func makeViewModel(
        premiumAccess: any PremiumAccessControlling,
        promptHistoryRepository: (any PremiumPromptHistoryRepository)? = nil
    ) -> ScannerViewModel {
        ScannerViewModel(
            gridColumns: 3,
            sensitivity: .medium,
            analysisService: mockAnalysisService,
            repository: mockRepository,
            reviewRepository: mockReviewRepository,
            cleanupCategoryRepository: mockCleanupCategoryRepository,
            cleanupSessionRepository: mockCleanupSessionRepository,
            cleanupService: mockCleanupService,
            cleanupHistoryRepository: mockCleanupHistoryRepository,
            premiumAccess: premiumAccess,
            scanUsageRepository: scanUsageRepository,
            premiumPromptHistoryRepository: promptHistoryRepository ?? premiumPromptHistoryRepository
        )
    }
    
    private func createMockCluster(id: UUID = UUID(), photoCount: Int) -> PhotoCluster {
        PhotoCluster(id: id, assets: [], createdAt: Date(), averageSimilarity: 0.95)
    }

    private func makeSnapshot(
        id: UUID = UUID(),
        assets: [String],
        favoriteIDs: Set<String> = []
    ) -> PhotoClusterSnapshot {
        PhotoClusterSnapshot(
            id: id,
            createdAt: Date(),
            averageSimilarity: 0.95,
            assets: assets.map { assetID in
                PhotoClusterAssetSnapshot(
                    localIdentifier: assetID,
                    creationDate: Date(timeIntervalSince1970: 100),
                    modificationDate: Date(timeIntervalSince1970: 100),
                    pixelWidth: favoriteIDs.contains(assetID) ? 1_200 : 800,
                    pixelHeight: favoriteIDs.contains(assetID) ? 1_200 : 800,
                    isFavorite: favoriteIDs.contains(assetID)
                )
            }
        )
    }
}

private struct TestError: LocalizedError {
    var errorDescription: String? { "Test error" }
}

private struct FailingCleanupInsightsProvider: CleanupInsightsProviding {
    func loadInsights() async throws -> CleanupInsights {
        throw TestError()
    }
}

@MainActor
private final class MutablePremiumAccessController: PremiumAccessControlling {
    var unlocksAdvancedFilters: Bool
    let entitlementState = PremiumEntitlementState.unknown

    init(unlocksAdvancedFilters: Bool) {
        self.unlocksAdvancedFilters = unlocksAdvancedFilters
    }

    func access(
        to feature: PremiumFeature,
        context: PremiumAccessContext
    ) -> PremiumAccessDecision {
        if feature == .advancedFilters, unlocksAdvancedFilters {
            return .allowed
        }
        return PremiumAccessPolicy.decision(for: feature, context: context, isPremium: false)
    }
}

@MainActor
private final class MutableEntitlementPremiumAccessController: PremiumAccessControlling {
    var entitlementState: PremiumEntitlementState

    init(entitlementState: PremiumEntitlementState) {
        self.entitlementState = entitlementState
    }

    func access(
        to feature: PremiumFeature,
        context: PremiumAccessContext
    ) -> PremiumAccessDecision {
        PremiumAccessPolicy.decision(
            for: feature,
            context: context,
            isPremium: entitlementState.isPremium
        )
    }
}

private actor SuspendedPremiumPromptHistoryRepository: PremiumPromptHistoryRepository {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var claimCalls = 0
    private var releaseCalls = 0

    func claimPostFirstUsefulScanPrompt() async -> Bool {
        claimCalls += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilClaimCallCount(_ expectedCount: Int) async {
        while claimCalls < expectedCount {
            await Task.yield()
        }
    }

    func resumeClaim(returning result: Bool) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    func currentClaimCallCount() -> Int {
        claimCalls
    }

    func releasePostFirstUsefulScanPromptClaim() {
        releaseCalls += 1
    }

    func currentReleaseCallCount() -> Int {
        releaseCalls
    }
}

private final class LockedDateProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func set(_ date: Date) {
        lock.lock()
        self.date = date
        lock.unlock()
    }
}

private actor SuspendedScanUsageRepository: ScanUsageRepository {
    private var loadContinuations: [CheckedContinuation<MonthlyScanUsage?, Never>] = []
    private var loads = 0
    private var usage: MonthlyScanUsage?

    func loadMonthlyUsage(at date: Date) async -> MonthlyScanUsage? {
        loads += 1
        return await withCheckedContinuation { continuation in
            loadContinuations.append(continuation)
        }
    }

    func initializeMonthlyUsage(_ usage: MonthlyScanUsage) {
        guard self.usage == nil else { return }
        self.usage = usage
    }

    func recordCompletedScan(at date: Date) -> MonthlyScanUsage {
        let current = usage ?? Self.makeUsage(count: 0, date: date)
        let updated = Self.makeUsage(count: current.completedScanCount + 1, date: date)
        usage = updated
        return updated
    }

    func waitUntilLoadCallCount(_ expectedCount: Int) async {
        while loads < expectedCount {
            await Task.yield()
        }
    }

    func resumeNextLoad(returning usage: MonthlyScanUsage?) {
        self.usage = usage
        loadContinuations.removeFirst().resume(returning: usage)
    }

    func loadCallCount() -> Int { loads }

    private static func makeUsage(count: Int, date: Date) -> MonthlyScanUsage {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: components) ?? date
        return MonthlyScanUsage(
            periodStart: start,
            nextResetDate: calendar.date(byAdding: .month, value: 1, to: start) ?? date,
            completedScanCount: count
        )
    }
}

private actor SuspendedCachedLoadPhotoClusterRepository: PhotoClusterRepository {
    private var loadContinuations: [CheckedContinuation<[PhotoCluster], Error>] = []
    private var loadCalls = 0
    private var savedClusters: [PhotoCluster] = []
    private var lastScanDate: Date?

    func loadClusters() async throws -> [PhotoCluster] {
        loadCalls += 1
        return try await withCheckedThrowingContinuation { continuation in
            loadContinuations.append(continuation)
        }
    }

    func loadClusterSnapshots() async throws -> [PhotoClusterSnapshot] { [] }

    func saveClusters(_ clusters: [PhotoCluster]) async throws {
        savedClusters = clusters
    }

    func deleteAllClusters() async throws {
        savedClusters = []
    }

    func getLastScanDate() async -> Date? { lastScanDate }

    func updateLastScanDate(_ date: Date) async throws {
        lastScanDate = date
    }

    func hasGalleryChanged() async -> Bool { false }

    func waitUntilLoadClustersCallCount(_ expectedCount: Int) async {
        while loadCalls < expectedCount {
            await Task.yield()
        }
    }

    func resumeNextLoadClusters(returning clusters: [PhotoCluster]) {
        loadContinuations.removeFirst().resume(returning: clusters)
    }
}

actor MockScanUsageRepository: ScanUsageRepository {
    private var usage: MonthlyScanUsage?
    private var records = 0

    init(count: Int? = 0) {
        self.usage = count.map { Self.makeUsage(count: $0) }
    }

    func loadMonthlyUsage(at date: Date) -> MonthlyScanUsage? {
        guard let usage else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard calendar.isDate(usage.periodStart, equalTo: date, toGranularity: .month) else {
            let reset = Self.makeUsage(count: 0, date: date)
            self.usage = reset
            return reset
        }
        return usage
    }

    func initializeMonthlyUsage(_ usage: MonthlyScanUsage) {
        guard self.usage == nil else { return }
        self.usage = usage
    }

    func recordCompletedScan(at date: Date) -> MonthlyScanUsage {
        records += 1
        let current = loadMonthlyUsage(at: date)
        let next = (current?.completedScanCount ?? 0) + 1
        let updated = Self.makeUsage(count: next, date: date)
        usage = updated
        return updated
    }

    func setCompletedScanCount(_ count: Int?) {
        usage = count.map { Self.makeUsage(count: $0) }
    }

    func setMonthlyUsage(count: Int, date: Date) {
        usage = Self.makeUsage(count: count, date: date)
    }

    func currentCount() -> Int { usage?.completedScanCount ?? 0 }
    func recordCallCount() -> Int { records }

    private static func makeUsage(count: Int, date: Date = Date()) -> MonthlyScanUsage {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: components) ?? date
        return MonthlyScanUsage(
            periodStart: start,
            nextResetDate: calendar.date(byAdding: .month, value: 1, to: start) ?? date,
            completedScanCount: count
        )
    }
}

private actor SuspendedPhotoAnalysisService: PhotoAnalysisService {
    private var continuations: [CheckedContinuation<[PhotoCluster], Error>] = []
    private var progressHandlers: [@Sendable (Double) -> Void] = []
    private var analyzeCallCount = 0
    private var concurrentAnalyzeCount = 0
    private var maximumConcurrentCount = 0

    func analyzePhotoLibrary(
        sensitivity: Float,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [PhotoCluster] {
        analyzeCallCount += 1
        concurrentAnalyzeCount += 1
        maximumConcurrentCount = max(maximumConcurrentCount, concurrentAnalyzeCount)
        defer { concurrentAnalyzeCount -= 1 }
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            progressHandlers.append(progress)
        }
    }

    func summarizeCleanupCategories() async throws -> [CleanupCategorySummary] { [] }
    func refreshCleanupCategories() async throws -> [CleanupCategorySummary] { [] }
    func loadAssets(for category: CleanupCategoryKind) async throws -> [PHAsset] { [] }
    func calculateSimilarity(asset1: PHAsset, asset2: PHAsset) async throws -> Float { 0 }

    func waitUntilAnalyzeCallCount(_ expectedCount: Int) async {
        while analyzeCallCount < expectedCount {
            await Task.yield()
        }
    }

    func resumeNext(returning clusters: [PhotoCluster]) {
        progressHandlers.removeFirst()
        continuations.removeFirst().resume(returning: clusters)
    }

    func publishProgress(_ progress: Double) {
        progressHandlers.first?(progress)
    }

    func currentAnalyzeCallCount() -> Int {
        analyzeCallCount
    }

    func maximumConcurrentAnalyzeCount() -> Int {
        maximumConcurrentCount
    }
}
