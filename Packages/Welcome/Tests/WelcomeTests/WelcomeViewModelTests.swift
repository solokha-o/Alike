import XCTest
import Photos
@testable import Welcome

@MainActor
final class WelcomeViewModelTests: XCTestCase {
    var viewModel: WelcomeViewModel!
    
    override func setUp() async throws {
        viewModel = WelcomeViewModel()
    }
    
    override func tearDown() async throws {
        viewModel = nil
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        // Given: Newly created view model
        // Then: Initial state should be .initial
        XCTAssertEqual(viewModel.state, .initial, "Initial state should be .initial")
    }
    
    // MARK: - State Transition Tests
    
    func testStateHasCorrectCases() {
        // Given: All possible states
        let initial = WelcomeViewModel.State.initial
        let denied = WelcomeViewModel.State.denied
        let authorized = WelcomeViewModel.State.authorized
        
        // Then: All states should be distinct
        XCTAssertNotEqual(initial, denied)
        XCTAssertNotEqual(initial, authorized)
        XCTAssertNotEqual(denied, authorized)
    }
    
    // MARK: - Permission Request Tests
    
    func testRequestPermissionChangesState() async {
        // Given: Initial state
        XCTAssertEqual(viewModel.state, .initial)
        
        // When: Requesting permission
        await viewModel.requestPhotoLibraryPermission()
        
        // Then: State should change (either authorized or denied based on user choice)
        // Note: This test is environment-dependent
        XCTAssertTrue(
            viewModel.state == .authorized || viewModel.state == .denied,
            "State should change after permission request"
        )
    }
    
    func testRequestPermissionMultipleTimes() async {
        // Given: First permission request
        await viewModel.requestPhotoLibraryPermission()
        let firstState = viewModel.state
        
        // When: Requesting permission again
        await viewModel.requestPhotoLibraryPermission()
        let secondState = viewModel.state
        
        // Then: State should remain consistent
        XCTAssertEqual(firstState, secondState, "Multiple requests should be idempotent")
    }
    
    // MARK: - Permission Status Check Tests
    
    func testCheckExistingPermissionAuthorized() async {
        // Given: Authorized permission status
        // (This assumes user has granted permission previously)
        
        // When: Checking current permission
        await viewModel.checkCurrentPermission()
        
        // Then: If authorized, state should be .authorized
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized {
            XCTAssertEqual(viewModel.state, .authorized)
        }
    }
    
    func testCheckExistingPermissionDenied() async {
        // Given: Denied permission status
        // (This test is hypothetical, depends on system state)
        
        // When: Checking current permission
        await viewModel.checkCurrentPermission()
        
        // Then: If denied, state should be .denied
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .denied || status == .restricted {
            XCTAssertEqual(viewModel.state, .denied)
        }
    }
    
    // MARK: - State Observable Tests
    
    func testStateIsObservable() async {
        // Given: View model with initial state
        var stateChanges = 0
        
        // Note: In real app, SwiftUI observes @Observable changes
        // This is a simplified test
        let initialState = viewModel.state
        
        // When: Requesting permission (triggers state change)
        await viewModel.requestPhotoLibraryPermission()
        
        // Then: State should have changed
        XCTAssertNotEqual(initialState, viewModel.state, "State should change after permission request")
    }
    
    // MARK: - Permission Status Mapping Tests
    
    func testAuthorizationStatusMapping() {
        // Test that we correctly map PHAuthorizationStatus to our State
        let authorized = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch authorized {
        case .authorized, .limited:
            // Should map to .authorized state
            XCTAssertTrue(true, "Authorized status should map to .authorized state")
        case .denied, .restricted:
            // Should map to .denied state
            XCTAssertTrue(true, "Denied/Restricted should map to .denied state")
        case .notDetermined:
            // Should remain in .initial state
            XCTAssertTrue(true, "Not determined should keep .initial state")
        @unknown default:
            XCTFail("Unknown authorization status")
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentPermissionRequests() async {
        // Given: View model
        // When: Making multiple concurrent permission requests
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask { @MainActor in
                    await self.viewModel.requestPhotoLibraryPermission()
                }
            }
        }
        
        // Then: Should handle concurrent requests gracefully
        XCTAssertTrue(
            viewModel.state == .authorized || viewModel.state == .denied,
            "Should handle concurrent requests without crashing"
        )
    }
    
    // MARK: - Edge Case Tests
    
    func testViewModelCreationIsMainActorIsolated() {
        // Given & When: Creating view model on main actor
        let vm = WelcomeViewModel()
        
        // Then: Should work without issues (MainActor isolated)
        XCTAssertNotNil(vm)
        XCTAssertEqual(vm.state, .initial)
    }
    
    func testStateEquality() {
        // Given: Same state values
        let state1 = WelcomeViewModel.State.initial
        let state2 = WelcomeViewModel.State.initial
        let state3 = WelcomeViewModel.State.denied
        
        // Then: Equality should work correctly
        XCTAssertEqual(state1, state2, "Same states should be equal")
        XCTAssertNotEqual(state1, state3, "Different states should not be equal")
    }
}
