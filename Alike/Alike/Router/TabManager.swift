//
//  TabManager.swift
//  Alike
//
//  Created by Oleksand S on 27.01.2026.
//

import SwiftUI

/// Manages tab navigation and state
@MainActor
@Observable
final class TabManager {
    // MARK: - Tab Definition
    enum Tab: String, CaseIterable, Hashable {
        case scanner
        case cleanup
        case settings
        
        var title: String {
            switch self {
            case .scanner: return AlikeL10n.Tab.scanner
            case .cleanup: return AlikeL10n.Tab.cleanup
            case .settings: return AlikeL10n.Tab.settings
            }
        }
        
        var icon: String {
            switch self {
            case .scanner: return "viewfinder"
            case .cleanup: return "photo.stack"
            case .settings: return "gear"
            }
        }
    }
    
    // MARK: - State
    var selectedTab: Tab = .scanner
    var shouldStartScan = false
    var needsRescan = false
    
    // MARK: - Actions
    func navigateToScanner(andStartScan: Bool = false) {
        selectedTab = .scanner
        if andStartScan {
            shouldStartScan = true
        }
    }

    func navigateToCleanup() {
        selectedTab = .cleanup
    }
    
    func requestRescan() {
        needsRescan = true
    }
    
    func triggerRescan() {
        needsRescan = false
        navigateToScanner(andStartScan: true)
    }
    
    func dismissRescan() {
        needsRescan = false
    }
}
