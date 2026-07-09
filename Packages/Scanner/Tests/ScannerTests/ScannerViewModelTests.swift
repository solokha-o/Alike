import XCTest
import Photos
import Core
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
    var premiumAccess: MockPremiumAccessController!
    
    override func setUp() async throws {
        mockAnalysisService = MockPhotoAnalysisService()
        mockRepository = MockPhotoClusterRepository()
        mockReviewRepository = MockClusterReviewStateRepository()
        mockCleanupCategoryRepository = MockCleanupCategorySnapshotRepository()
        mockCleanupSessionRepository = MockCleanupSessionRepository()
        mockCleanupService = MockPhotoCleanupService()
        mockCleanupHistoryRepository = MockCleanupHistoryRepository()
        premiumAccess = MockPremiumAccessController()
        viewModel = ScannerViewModel(
            gridColumns: 3,
            sensitivity: .medium,
            analysisService: mockAnalysisService,
            repository: mockRepository,
            reviewRepository: mockReviewRepository,
            cleanupCategoryRepository: mockCleanupCategoryRepository,
            cleanupSessionRepository: mockCleanupSessionRepository,
            cleanupService: mockCleanupService,
            cleanupHistoryRepository: mockCleanupHistoryRepository,
            premiumAccess: premiumAccess
        )
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

    func testCleanupEntryClusterPrefersNotReviewedThenInReviewThenFirst() async {
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

        await mockReviewRepository.setStoredStates([:])
        await viewModel.loadReviewStates()
        let fallback = [reviewed]
        XCTAssertEqual(viewModel.cleanupEntryCluster(from: fallback)?.id, reviewedID)
    }

    func testHandleCleanupCompletedInvalidatesCachesAndRefreshesResults() async {
        let cluster = createMockCluster(photoCount: 2)
        let completionRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 2,
            estimatedSavingsBytes: 1_024
        )
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.success([cluster]))
        await mockAnalysisService.setRefreshCleanupCategoriesResult(.success([
            CleanupCategorySummary(kind: .screenshots, assetCount: 3, estimatedSavingsBytes: 300)
        ]))
        await mockCleanupHistoryRepository.setEntries([completionRecord])

        await viewModel.handleCleanupCompleted(completionRecord)

        let didDeleteClusters = await mockRepository.didCallDeleteAllClusters
        let didDeleteReviewStates = await mockReviewRepository.didCallDeleteAllReviewStates
        let didDeleteSession = await mockCleanupSessionRepository.didCallDeleteActiveSession

        XCTAssertTrue(didDeleteClusters)
        XCTAssertTrue(didDeleteReviewStates)
        XCTAssertTrue(didDeleteSession)

        if case .results(let clusters) = viewModel.state {
            XCTAssertEqual(clusters.count, 1)
        } else {
            XCTFail("Expected refreshed results state")
        }

        XCTAssertEqual(viewModel.cleanupRefreshState, .success(completionRecord))
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

    func testHandleCleanupCompletedFailureClearsStaleResultsAndShowsRetryState() async {
        let oldCluster = createMockCluster(photoCount: 2)
        let completionRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 1,
            estimatedSavingsBytes: 512
        )
        viewModel.state = .results([oldCluster])
        await mockAnalysisService.setAnalyzePhotoLibraryResult(.failure(TestError()))
        await mockCleanupHistoryRepository.setEntries([completionRecord])

        await viewModel.handleCleanupCompleted(completionRecord)

        if case .idle = viewModel.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected idle state after failed cleanup refresh")
        }

        switch viewModel.cleanupRefreshState {
        case .failed(let record, let message):
            XCTAssertEqual(record, completionRecord)
            XCTAssertFalse(message.isEmpty)
        default:
            XCTFail("Expected failed cleanup refresh state")
        }

        XCTAssertEqual(viewModel.cleanupInsights.totalDeletedItems, 1)
        XCTAssertEqual(viewModel.cleanupInsights.totalSavedBytes, 512)
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
