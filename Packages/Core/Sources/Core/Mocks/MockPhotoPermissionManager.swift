import Photos

#if DEBUG

/// Mock implementation of PhotoPermissionManager for SwiftUI previews and unit tests.
@MainActor
public final class MockPhotoPermissionManager: PhotoPermissionManager {
    public var authorizationStatus: PHAuthorizationStatus
    public var requestAuthorizationResult: PHAuthorizationStatus
    public var didCallRequestAuthorization = false
    public var didCallOpenSettings = false
    
    public init(authorizationStatus: PHAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
        self.requestAuthorizationResult = authorizationStatus
    }
    
    public var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }
    
    public func requestAuthorization() async -> PHAuthorizationStatus {
        didCallRequestAuthorization = true
        authorizationStatus = requestAuthorizationResult
        return requestAuthorizationResult
    }
    
    public func openSettings() {
        didCallOpenSettings = true
    }
}

#endif
