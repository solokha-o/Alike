import Testing
import Photos
import Core
@testable import Welcome

@MainActor
@Suite struct WelcomeViewModelTests {
    let viewModel: WelcomeViewModel
    let mockPermissionManager: MockPhotoPermissionManager
    
    init() {
        mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .notDetermined)
        viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
    }
    
    // MARK: - Initial State Tests
    
    @Test func testInitialState() {
        #expect(viewModel.authorizationStatus == .notDetermined)
        #expect(!viewModel.isAuthorized)
    }

    @Test func testDataDeletionReplayReplaysOnboardingWithoutRequestingPermission() {
        #expect(WelcomeMode.dataDeletionReplay.replaysOnboarding)
        #expect(!WelcomeMode.dataDeletionReplay.requestsPhotoPermission)
        #expect(!WelcomeMode.permissionRequest.replaysOnboarding)
        #expect(WelcomeMode.permissionRequest.requestsPhotoPermission)
    }
    
    @Test func testIsAuthorizedWhenAuthorized() {
        let mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .authorized)
        let viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
        
        #expect(viewModel.isAuthorized)
    }
    
    @Test func testIsAuthorizedWhenLimited() {
        let mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .limited)
        let viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
        
        #expect(viewModel.isAuthorized)
    }
    
    @Test func testIsNotAuthorizedWhenDenied() {
        let mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .denied)
        let viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
        
        #expect(!viewModel.isAuthorized)
    }
    
    // MARK: - Permission Request Tests
    
    @Test func testRequestPermissionSuccess() async {
        mockPermissionManager.requestAuthorizationResult = .authorized
        
        await viewModel.requestPermission()
        
        #expect(mockPermissionManager.didCallRequestAuthorization)
        #expect(viewModel.authorizationStatus == .authorized)
        #expect(viewModel.isAuthorized)
    }
    
    @Test func testRequestPermissionDenied() async {
        mockPermissionManager.requestAuthorizationResult = .denied
        
        await viewModel.requestPermission()
        
        #expect(mockPermissionManager.didCallRequestAuthorization)
        #expect(viewModel.authorizationStatus == .denied)
        #expect(!viewModel.isAuthorized)
    }
    
    @Test func testRequestPermissionLimited() async {
        mockPermissionManager.requestAuthorizationResult = .limited
        
        await viewModel.requestPermission()
        
        #expect(mockPermissionManager.didCallRequestAuthorization)
        #expect(viewModel.authorizationStatus == .limited)
        #expect(viewModel.isAuthorized)
    }
    
    // MARK: - Settings Tests
    
    @Test func testOpenSettings() {
        viewModel.openSettings()
        
        #expect(mockPermissionManager.didCallOpenSettings)
    }
    
    // MARK: - Check Status Tests
    
    @Test func testCheckStatus() {
        mockPermissionManager.authorizationStatus = .authorized
        
        viewModel.checkStatus()
        
        #expect(viewModel.authorizationStatus == .authorized)
    }
}
