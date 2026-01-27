import XCTest
import Photos
import Core
@testable import Welcome

@MainActor
final class WelcomeViewModelTests: XCTestCase {
    var viewModel: WelcomeViewModel!
    var mockPermissionManager: MockPhotoPermissionManager!
    
    override func setUp() async throws {
        mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .notDetermined)
        viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
    }
    
    override func tearDown() async throws {
        viewModel = nil
        mockPermissionManager = nil
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        XCTAssertEqual(viewModel.authorizationStatus, .notDetermined)
        XCTAssertFalse(viewModel.isAuthorized)
    }
    
    func testIsAuthorizedWhenAuthorized() {
        mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .authorized)
        viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
        
        XCTAssertTrue(viewModel.isAuthorized)
    }
    
    func testIsAuthorizedWhenLimited() {
        mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .limited)
        viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
        
        XCTAssertTrue(viewModel.isAuthorized)
    }
    
    func testIsNotAuthorizedWhenDenied() {
        mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .denied)
        viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
        
        XCTAssertFalse(viewModel.isAuthorized)
    }
    
    // MARK: - Permission Request Tests
    
    func testRequestPermissionSuccess() async {
        mockPermissionManager.requestAuthorizationResult = .authorized
        
        await viewModel.requestPermission()
        
        XCTAssertTrue(mockPermissionManager.didCallRequestAuthorization)
        XCTAssertEqual(viewModel.authorizationStatus, .authorized)
        XCTAssertTrue(viewModel.isAuthorized)
    }
    
    func testRequestPermissionDenied() async {
        mockPermissionManager.requestAuthorizationResult = .denied
        
        await viewModel.requestPermission()
        
        XCTAssertTrue(mockPermissionManager.didCallRequestAuthorization)
        XCTAssertEqual(viewModel.authorizationStatus, .denied)
        XCTAssertFalse(viewModel.isAuthorized)
    }
    
    func testRequestPermissionLimited() async {
        mockPermissionManager.requestAuthorizationResult = .limited
        
        await viewModel.requestPermission()
        
        XCTAssertTrue(mockPermissionManager.didCallRequestAuthorization)
        XCTAssertEqual(viewModel.authorizationStatus, .limited)
        XCTAssertTrue(viewModel.isAuthorized)
    }
    
    // MARK: - Settings Tests
    
    func testOpenSettings() {
        viewModel.openSettings()
        
        XCTAssertTrue(mockPermissionManager.didCallOpenSettings)
    }
    
    // MARK: - Check Status Tests
    
    func testCheckStatus() {
        mockPermissionManager.authorizationStatus = .authorized
        
        viewModel.checkStatus()
        
        XCTAssertEqual(viewModel.authorizationStatus, .authorized)
    }
}
