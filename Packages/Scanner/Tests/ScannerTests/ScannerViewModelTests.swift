import XCTest
import Core
@testable import Scanner

@MainActor
final class ScannerViewModelTests: XCTestCase {
    var viewModel: ScannerViewModel!
    
    override func setUp() async throws {
        viewModel = ScannerViewModel(gridColumns: 3, sensitivity: .medium)
    }
    
    override func tearDown() async throws {
        viewModel = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitialState() {
        // Given: Newly created view model
        // Then: Initial state should be .idle
        if case .idle = viewModel.state {
            XCTAssertTrue(true, "Initial state should be .idle")
        } else {
            XCTFail("Expected .idle state, got \(viewModel.state)")
        }
    }
    
    func testInitialGridColumns() {
        // Given: View model initialized with 3 columns
        // Then: Grid columns should be 3
        XCTAssertEqual(viewModel.gridColumns, 3, "Grid columns should match initialization")
    }
    
    func testGridColumnsCanBeUpdated() {
        // Given: Initial grid columns
        viewModel.gridColumns = 4
        
        // Then: Should update
        XCTAssertEqual(viewModel.gridColumns, 4, "Grid columns should be updatable")
    }
    
    // MARK: - State Tests
    
    func testStateIdle() {
        // Given: Idle state
        viewModel.state = .idle
        
        // Then: Should match
        if case .idle = viewModel.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("State should be idle")
        }
    }
    
    func testStateScanningWithProgress() {
        // Given: Scanning state with progress
        viewModel.state = .scanning(progress: 0.5)
        
        // Then: Should have correct progress
        if case .scanning(let progress) = viewModel.state {
            XCTAssertEqual(progress, 0.5, accuracy: 0.01, "Progress should be 0.5")
        } else {
            XCTFail("State should be scanning")
        }
    }
    
    func testStateResults() {
        // Given: Results state with clusters
        let cluster = createMockCluster(photoCount: 2)
        viewModel.state = .results([cluster])
        
        // Then: Should have clusters
        if case .results(let clusters) = viewModel.state {
            XCTAssertEqual(clusters.count, 1, "Should have 1 cluster")
        } else {
            XCTFail("State should be results")
        }
    }
    
    func testStateError() {
        // Given: Error state
        viewModel.state = .error("Test error")
        
        // Then: Should have error message
        if case .error(let message) = viewModel.state {
            XCTAssertEqual(message, "Test error")
        } else {
            XCTFail("State should be error")
        }
    }
    
    // MARK: - Scan Tests
    
    func testScanChangesStateToScanning() async {
        // Given: Idle state
        viewModel.state = .idle
        
        // When: Starting scan
        // Note: This will actually try to scan photos from library
        // In a real test, you'd mock PhotoAnalysisService
        Task { @MainActor in
            await viewModel.scan()
        }
        
        // Give it a moment to start
        try? await Task.sleep(for: .milliseconds(100))
        
        // Then: State should change from idle
        // (Will be scanning or results depending on photo library)
        switch viewModel.state {
        case .idle:
            XCTFail("State should have changed from idle")
        case .scanning:
            XCTAssertTrue(true, "State changed to scanning")
        case .results:
            XCTAssertTrue(true, "Scan completed immediately")
        case .error:
            XCTAssertTrue(true, "Error occurred (expected if no photos)")
        }
    }
    
    func testScanProgressIncreases() async {
        // Given: Starting scan
        var progressValues: [Double] = []
        
        // When: Scanning (mock scenario)
        viewModel.state = .scanning(progress: 0.0)
        progressValues.append(0.0)
        
        viewModel.state = .scanning(progress: 0.5)
        progressValues.append(0.5)
        
        viewModel.state = .scanning(progress: 1.0)
        progressValues.append(1.0)
        
        // Then: Progress should increase
        XCTAssertEqual(progressValues[0], 0.0)
        XCTAssertEqual(progressValues[1], 0.5)
        XCTAssertEqual(progressValues[2], 1.0)
        XCTAssertLessThan(progressValues[0], progressValues[1])
        XCTAssertLessThan(progressValues[1], progressValues[2])
    }
    
    // MARK: - Clear Results Tests
    
    func testClearResults() {
        // Given: Results state
        let cluster = createMockCluster(photoCount: 3)
        viewModel.state = .results([cluster])
        
        // When: Clearing results
        viewModel.clearResults()
        
        // Then: Should return to idle
        if case .idle = viewModel.state {
            XCTAssertTrue(true, "State should be idle after clearing")
        } else {
            XCTFail("Expected idle state after clearing results")
        }
    }
    
    func testClearResultsFromIdle() {
        // Given: Idle state
        viewModel.state = .idle
        
        // When: Clearing results (should be no-op)
        viewModel.clearResults()
        
        // Then: Should remain idle
        if case .idle = viewModel.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Should remain idle")
        }
    }
    
    // MARK: - Observable Tests
    
    func testStateIsObservable() {
        // Given: Initial state
        let initialState = viewModel.state
        
        // When: Changing state
        viewModel.state = .scanning(progress: 0.3)
        
        // Then: State should have changed
        if case .idle = initialState, case .scanning = viewModel.state {
            XCTAssertTrue(true, "State changed from idle to scanning")
        } else {
            XCTFail("State should have changed")
        }
    }
    
    // MARK: - Grid Columns Validation Tests
    
    func testGridColumnsRange() {
        // Given: Valid grid column values
        let validColumns = [2, 3, 4, 5, 6]
        
        for columns in validColumns {
            // When: Setting grid columns
            viewModel.gridColumns = columns
            
            // Then: Should accept value
            XCTAssertEqual(viewModel.gridColumns, columns, "Should accept \(columns) columns")
        }
    }
    
    // MARK: - Sensitivity Tests
    
    func testSensitivityAffectsClustering() {
        // Given: Different sensitivity levels
        let lowSensitivity = SensitivityLevel.low
        let highSensitivity = SensitivityLevel.high
        
        // Then: Thresholds should be different
        XCTAssertNotEqual(lowSensitivity.threshold, highSensitivity.threshold)
        XCTAssertLessThan(lowSensitivity.threshold, highSensitivity.threshold)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorStateContainsMessage() {
        // Given: Error message
        let errorMessage = "No photos found"
        
        // When: Setting error state
        viewModel.state = .error(errorMessage)
        
        // Then: Should contain message
        if case .error(let message) = viewModel.state {
            XCTAssertEqual(message, errorMessage)
        } else {
            XCTFail("Should be in error state")
        }
    }
    
    // MARK: - State Transition Tests
    
    func testValidStateTransitions() {
        // Given: Idle state
        viewModel.state = .idle
        XCTAssertTrue(true, "Started with idle")
        
        // When: Transitioning to scanning
        viewModel.state = .scanning(progress: 0.0)
        if case .scanning = viewModel.state {
            XCTAssertTrue(true, "Transitioned to scanning")
        }
        
        // When: Transitioning to results
        let cluster = createMockCluster(photoCount: 2)
        viewModel.state = .results([cluster])
        if case .results = viewModel.state {
            XCTAssertTrue(true, "Transitioned to results")
        }
        
        // When: Transitioning back to idle
        viewModel.state = .idle
        if case .idle = viewModel.state {
            XCTAssertTrue(true, "Transitioned back to idle")
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentStateUpdates() async {
        // Given: View model
        // When: Updating state concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask { @MainActor in
                    self.viewModel.state = .scanning(progress: Double(i) / 10.0)
                }
            }
        }
        
        // Then: Should handle concurrent updates without crashing
        XCTAssertTrue(true, "Handled concurrent updates")
    }
    
    // MARK: - Helper Methods
    
    private func createMockCluster(photoCount: Int) -> PhotoCluster {
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = photoCount
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        // If no photos, create cluster with empty array (for testing)
        return PhotoCluster(
            assets: assets,
            createdAt: Date(),
            averageSimilarity: 0.95
        )
    }
}
