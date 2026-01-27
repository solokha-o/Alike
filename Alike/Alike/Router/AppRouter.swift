//
//  AppRouter.swift
//  Alike
//
//  Created by Oleksand S on 27.01.2026.
//

import SwiftUI
import PhotoAnalysis
import Photos

/// Manages app-wide navigation state
@MainActor
@Observable
final class AppRouter {
    // MARK: - Route Definition
    enum Route {
        case launch
        case welcome
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
        // Якщо доступ вже є - пропускаємо Welcome
        if permissionManager.isAuthorized {
            currentRoute = .main
        } else {
            currentRoute = .welcome
        }
    }
    
    func completeWelcome() {
        currentRoute = .main
    }
}
