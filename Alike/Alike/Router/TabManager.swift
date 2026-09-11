//
//  TabManager.swift
//  Alike
//
//  Created by Oleksand S on 27.01.2026.
//

import Cleanup
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
    /// Where inside cleanup something outside the app asked to land — the same shape of
    /// carried intent as `shouldStartScan`, which `ScannerView` already consumes as a
    /// binding. `CleanupView` clears it once it has acted on it.
    var pendingCleanupEntry: CleanupWidgetEntry?
    
    // MARK: - Actions
    func navigateToScanner(andStartScan: Bool = false) {
        selectedTab = .scanner
        if andStartScan {
            shouldStartScan = true
        }
    }

    /// `entry` defaults to `nil`, so the existing no-argument call sites are unchanged
    /// and still mean "just show the tab".
    func navigateToCleanup(entry: CleanupWidgetEntry? = nil) {
        selectedTab = .cleanup
        if let entry {
            pendingCleanupEntry = entry
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
