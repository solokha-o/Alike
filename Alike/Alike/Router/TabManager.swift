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
        case settings
        
        var titleKey: LocalizedStringKey {
            switch self {
            case .scanner: return "Scanner"
            case .settings: return "Settings"
            }
        }
        
        var icon: String {
            switch self {
            case .scanner: return "photo.stack"
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
