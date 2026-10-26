import Testing
import Photos
import Core
@testable import Welcome

@MainActor
@Suite struct WelcomeViewModelTests {
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
        mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .authorized)
        viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
        
        #expect(viewModel.isAuthorized)
    }
    
    @Test func testIsAuthorizedWhenLimited() {
        mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .limited)
        viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
        
        #expect(viewModel.isAuthorized)
    }
    
    @Test func testIsNotAuthorizedWhenDenied() {
        mockPermissionManager = MockPhotoPermissionManager(authorizationStatus: .denied)
        viewModel = WelcomeViewModel(permissionManager: mockPermissionManager)
        
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
