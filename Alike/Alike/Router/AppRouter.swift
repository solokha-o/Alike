//
//  AppRouter.swift
//  Alike
//
//  Created by Oleksand S on 27.01.2026.
//

import SwiftUI
import PhotoAnalysis
import Photos
import Welcome

/// Manages app-wide navigation state
@MainActor
@Observable
final class AppRouter {
    // MARK: - Route Definition
    enum Route: Equatable {
        case launch
        case welcome(WelcomeMode)
        case main
    }
    
    // MARK: - State
    private(set) var currentRoute: Route = .launch
    private let permissionManager: PhotoPermissionManager
    
    // MARK: - Initialization
    init(permissionManager: PhotoPermissionManager) {
        self.permissionManager = permissionManager
    }
    
    // MARK: - Navigation
    func completeLaunch() async {
        if permissionManager.isAuthorized {
            currentRoute = .main
        } else {
            currentRoute = .welcome(.permissionRequest)
        }
    }
    
    func completeWelcome() {
        currentRoute = .main
    }

    func restartAfterDataDeletion() {
        currentRoute = .welcome(.dataDeletionReplay)
    }
}
