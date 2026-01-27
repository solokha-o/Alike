//
//  RootView.swift
//  Alike
//
//  Created by Oleksand S on 27.01.2026.
//

import SwiftUI
import Launch
import Welcome
import Scanner
import Settings
import Core

/// Root view that manages app navigation flow
struct RootView: View {
    @State private var router = AppRouter(permissionManager: PhotoPermissionManagerImpl())
    
    var body: some View {
        ZStack {
            switch router.currentRoute {
            case .launch:
                LaunchView(isCompleted: .init(
                    get: { false },
                    set: { _ in
                        Task {
                            await router.completeLaunch()
                        }
                    }
                ))
            case .welcome:
                WelcomeView(isCompleted: .init(
                    get: { false },
                    set: { _ in router.completeWelcome() }
                ))
            case .main:
                MainTabView()
            }
        }
        .animation(.smooth, value: router.currentRoute)
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @State private var tabManager = TabManager()
    @AppStorage("gridColumns") private var gridColumns = GridConfiguration.current.defaultColumns
    @AppStorage("sensitivity") private var sensitivityRaw = SensitivityLevel.medium.rawValue
    
    private var sensitivity: Binding<SensitivityLevel> {
        Binding(
            get: { SensitivityLevel(rawValue: sensitivityRaw) ?? .medium },
            set: { sensitivityRaw = $0.rawValue }
        )
    }
    
    var body: some View {
        TabView(selection: Bindable(tabManager).selectedTab) {
            ScannerView(
                gridColumns: $gridColumns,
                sensitivity: sensitivity,
                shouldStartScan: Bindable(tabManager).shouldStartScan
            )
            .tabItem {
                Label(TabManager.Tab.scanner.title, systemImage: TabManager.Tab.scanner.icon)
            }
            .tag(TabManager.Tab.scanner)
            
            SettingsView(
                gridColumns: $gridColumns,
                sensitivity: sensitivity,
                needsRescan: Bindable(tabManager).needsRescan
            )
            .tabItem {
                Label(TabManager.Tab.settings.title, systemImage: TabManager.Tab.settings.icon)
            }
            .tag(TabManager.Tab.settings)
        }
        .tint(.accent)
        .alert("Rescan Required", isPresented: Bindable(tabManager).needsRescan) {
            Button("Later", role: .cancel) {
                tabManager.dismissRescan()
            }
            Button("Rescan Now") {
                tabManager.triggerRescan()
            }
        } message: {
            Text("Changing sensitivity requires a new scan to take effect")
        }
    }
}
