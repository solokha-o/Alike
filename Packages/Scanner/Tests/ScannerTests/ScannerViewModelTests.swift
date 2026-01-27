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
        mockRepository.clustersToReturn = [mockCluster]
        
        await viewModel.loadCachedResults()
        
        if case .results(let clusters) = viewModel.state {
            XCTAssertEqual(clusters.count, 1)
        } else {
            XCTFail("Expected results state")
        }
    }
    
    func testLoadCachedResultsEmpty() async {
        mockRepository.clustersToReturn = []
        await viewModel.loadCachedResults()
        
        if case .idle = viewModel.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected idle state")
        }
    }
    
    // MARK: - Scan Tests
    
    func testScanCallsAnalysisService() async {
        let mockCluster = createMockCluster(photoCount: 3)
        mockAnalysisService.clustersToReturn = [mockCluster]
        
        await viewModel.scan()
        
        XCTAssertTrue(mockAnalysisService.analyzePhotoLibraryCalled)
        
        if case .results(let clusters) = viewModel.state {
            XCTAssertEqual(clusters.count, 1)
        }
    }
    
    func testScanSavesClusters() async {
        let mockCluster = createMockCluster(photoCount: 2)
        mockAnalysisService.clustersToReturn = [mockCluster]
        
        await viewModel.scan()
        
        XCTAssertTrue(mockRepository.saveClustersCalled)
        XCTAssertEqual(mockRepository.savedClusters.count, 1)
    }
    
    // MARK: - Clear Results Tests
    
    func testClearResults() {
        let cluster = createMockCluster(photoCount: 3)
        viewModel.state = .results([cluster])
        
        viewModel.clearResults()
        
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

// MARK: - Mocks

final class MockPhotoAnalysisService: PhotoAnalysisService {
    var clustersToReturn: [PhotoCluster] = []
    var analyzePhotoLibraryCalled = false
    
    func analyzePhotoLibrary(sensitivity: Float, progress: @Sendable @escaping (Double) -> Void) async throws -> [PhotoCluster] {
        analyzePhotoLibraryCalled = true
        progress(1.0)
        return clustersToReturn
    }
    
    func calculateSimilarity(between asset1: PHAsset, and asset2: PHAsset) async throws -> Float {
        return 0.9
    }
}

final class MockPhotoClusterRepository: PhotoClusterRepository {
    var clustersToReturn: [PhotoCluster] = []
    var saveClustersCalled = false
    var savedClusters: [PhotoCluster] = []
    var lastScanDate: Date?
    
    func loadClusters() async throws -> [PhotoCluster] {
        clustersToReturn
    }
    
    func saveClusters(_ clusters: [PhotoCluster]) async throws {
        saveClustersCalled = true
        savedClusters = clusters
    }
    
    func deleteAllClusters() async throws {
        clustersToReturn = []
    }
    
    func getLastScanDate() async -> Date? {
        lastScanDate
    }
    
    func updateLastScanDate(_ date: Date) async throws {
        lastScanDate = date
    }
    
    func hasGalleryChanged() async -> Bool {
        true
    }
}
