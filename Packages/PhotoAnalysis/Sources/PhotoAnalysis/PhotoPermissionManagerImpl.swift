import Photos
import UIKit
import Core

/// Permission manager for photo library access
@MainActor
public final class PhotoPermissionManagerImpl: PhotoPermissionManager {
    
    public init() {}
    
    public var authorizationStatus: PHAuthorizationStatus {
        if #available(iOS 14, *) {
            return PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            return PHPhotoLibrary.authorizationStatus()
        }
    }
    
    public func requestAuthorization() async -> PHAuthorizationStatus {
        if #available(iOS 14, *) {
            return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
    }
    
    public var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .limited:
            return true
        default:
            return false
        }
    }
    
    public func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        
        if UIApplication.shared.canOpenURL(settingsURL) {
            UIApplication.shared.open(settingsURL)
        }
    }
}
