import SwiftUI
import Photos
import PhotoAnalysis
import DesignSystem

@MainActor
@Observable
public final class WelcomeViewModel {
    private let permissionManager: PhotoPermissionManagerImpl
    
    public var authorizationStatus: PHAuthorizationStatus
    public var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }
    
    public init(permissionManager: PhotoPermissionManagerImpl = PhotoPermissionManagerImpl()) {
        self.permissionManager = permissionManager
        self.authorizationStatus = permissionManager.authorizationStatus
    }
    
    public func requestPermission() async {
        authorizationStatus = await permissionManager.requestAuthorization()
    }
    
    public func openSettings() {
        permissionManager.openSettings()
    }
    
    public func checkStatus() {
        authorizationStatus = permissionManager.authorizationStatus
    }
}
