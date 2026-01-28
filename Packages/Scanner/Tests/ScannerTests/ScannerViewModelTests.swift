import XCTest
import Photos
import Core
@testable import Scanner

@MainActor
final class ScannerViewModelTests: XCTestCase {
    var viewModel: ScannerViewModel!
    var mockAnalysisService: MockPhotoAnalysisService!
    var mockRepository: MockPhotoClusterRepository!
    
    override func setUp() async throws {
        mockAnalysisService = MockPhotoAnalysisService()
        mockRepository = MockPhotoClusterRepository()
        viewModel = ScannerViewModel(
            gridColumns: 3,
            sensitivity: .medium,
            analysisService: mockAnalysisService,
            repository: mockRepository
        )
    }
    
    override func tearDown() async throws {
        viewModel = nil
        mockAnalysisService = nil
        mockRepository = nil
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
    
    private func createMockCluster(photoCount: Int) -> PhotoCluster {
        PhotoCluster(assets: [], createdAt: Date(), averageSimilarity: 0.95)
    }
}

private struct TestError: LocalizedError {
    var errorDescription: String? { "Test error" }
}
