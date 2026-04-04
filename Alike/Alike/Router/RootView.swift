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
    private let tabs = TabManager.Tab.allCases
    @State private var tabManager = TabManager()
    @AppStorage("gridColumns") private var gridColumns = GridConfiguration.current.defaultColumns
    @AppStorage("sensitivity") private var sensitivityRaw = SensitivityLevel.medium.rawValue
    private let gridConfiguration = GridConfiguration.current
    
    private var sensitivity: Binding<SensitivityLevel> {
        Binding(
            get: { SensitivityLevel(rawValue: sensitivityRaw) ?? .medium },
            set: { sensitivityRaw = $0.rawValue }
        )
    }
    
    var body: some View {
        TabView(selection: Bindable(tabManager).selectedTab) {
            ForEach(tabs, id: \.self) { tab in
                tabView(for: tab)
                    .tabItem {
                        Label(tab.titleKey, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
        .tint(.accent)
        .task {
            let clamped = gridConfiguration.clampedColumns(gridColumns)
            if clamped != gridColumns {
                gridColumns = clamped
            }
        }
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
    
    @ViewBuilder
    private func tabView(for tab: TabManager.Tab) -> some View {
        switch tab {
        case .scanner:
            ScannerView(
                gridColumns: Binding(
                    get: { gridConfiguration.clampedColumns(gridColumns) },
                    set: { gridColumns = gridConfiguration.clampedColumns($0) }
                ),
                sensitivity: sensitivity,
                shouldStartScan: Bindable(tabManager).shouldStartScan
            )
        case .settings:
            SettingsView(
                gridColumns: Binding(
                    get: { gridConfiguration.clampedColumns(gridColumns) },
                    set: { gridColumns = gridConfiguration.clampedColumns($0) }
                ),
                sensitivity: sensitivity,
                needsRescan: Bindable(tabManager).needsRescan
            )
        }
    }
}
