//
//  TabManager.swift
//  Alike
//
//  Created by Oleksand S on 27.01.2026.
//

import Cleanup
import Core
import SwiftUI
import WidgetSupport

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

        /// The iOS 27 tab bar role: Scanner is the prominent tab, the others keep the
        /// default role. Only the iOS 27 `Tab` builder reads it; older systems keep `.tabItem`.
        @available(iOS 27.0, *)
        var tabRole: TabRole? {
            self == .scanner ? .prominent : nil
        }
    }
    
    // MARK: - State
    var selectedTab: Tab = .scanner
    var shouldStartScan = false
    var needsRescan = false
    /// `true` while `ScannerView` shows its paywall or the guide. Written by the scanner
    /// through a binding, read by anything that wants the home screen to itself.
    var isScannerModalPresented = false
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
    
    /// Where a widget tap lands. Every destination is the cleanup tab; the category ones
    /// also carry the entry `CleanupView` resolves (and gates) once its content loads.
    func follow(_ destination: WidgetDestination) {
        switch destination {
        case .cleanup:
            navigateToCleanup()
        case .resumeReview:
            navigateToCleanup(entry: .resumeReview)
        case .similarPhotos:
            navigateToCleanup(entry: .similarPhotos)
        case .screenshots:
            navigateToCleanup(entry: .category(.screenshots))
        case .blurredPhotos:
            navigateToCleanup(entry: .category(.blurredPhotos))
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
