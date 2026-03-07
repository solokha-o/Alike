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
    
    override func setUp() async throws {
        mockAnalysisService = MockPhotoAnalysisService()
        mockRepository = MockPhotoClusterRepository()
        mockReviewRepository = MockClusterReviewStateRepository()
        viewModel = ScannerViewModel(
            gridColumns: 3,
            sensitivity: .medium,
            analysisService: mockAnalysisService,
            repository: mockRepository,
            reviewRepository: mockReviewRepository
        )
    }
    
    override func tearDown() async throws {
        viewModel = nil
        mockAnalysisService = nil
        mockRepository = nil
        mockReviewRepository = nil
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
        await mockRepository.setLoadClustersResult(.success([mockCluster]))
        
        await viewModel.loadCachedResults()
        
        if case .results(let clusters) = viewModel.state {
            XCTAssertEqual(clusters.count, 1)
        } else {
            XCTFail("Expected results state")
        }
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
        
        await viewModel.startScanning()
        
        let didCall = await mockRepository.didCallSaveClusters
        XCTAssertTrue(didCall)
        
        let saved = await mockRepository.savedClusters
        XCTAssertEqual(saved.count, 1)
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
        await mockRepository.setHasGalleryChangedResult(true)
        let hasChanged = await viewModel.checkForGalleryChanges()
        let didCall = await mockRepository.didCallHasGalleryChanged
        XCTAssertTrue(hasChanged)
        XCTAssertTrue(didCall)
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
        let inReviewID = UUID()
        let notReviewedID = UUID()
        let unknownStateID = UUID()

        let clusters = [
            createMockCluster(id: reviewedID, photoCount: 3),
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

        XCTAssertEqual(progress.totalClusters, 3)
        XCTAssertEqual(progress.reviewedCount, 1)
        XCTAssertEqual(progress.inReviewCount, 1)
        XCTAssertEqual(progress.notReviewedCount, 1)
        XCTAssertEqual(progress.reviewedSavingsBytes, 3_000)
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
}

private struct TestError: LocalizedError {
    var errorDescription: String? { "Test error" }
}
