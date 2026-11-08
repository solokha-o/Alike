import Photos
#if canImport(UIKit)
import UIKit
#endif
import Core

/// Permission manager for photo library access
@MainActor
public final class PhotoPermissionManagerImpl: PhotoPermissionManager {
    public init() {}
    
    public var authorizationStatus: PHAuthorizationStatus {
        if #available(iOS 14, *) {
            PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            PHPhotoLibrary.authorizationStatus()
        }
    }
    
    public func requestAuthorization() async -> PHAuthorizationStatus {
        if #available(iOS 14, *) {
            await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
    }
    
    public var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .limited:
            true
        default:
            false
        }
    }
    
    public func openSettings() {
        #if os(iOS)
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        
        if UIApplication.shared.canOpenURL(settingsURL) {
            UIApplication.shared.open(settingsURL)
        }
        #endif
    }
}
