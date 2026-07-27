//
//  RootView.swift
//  Alike
//
//  Created by Oleksand S on 27.01.2026.
//

import os
import SwiftUI
import Launch
import Welcome
import Scanner
import Settings
import Core
import Cleanup
import Storage
import Purchases
import PurchasesUI

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
    @Environment(\.scenePhase) private var scenePhase
    private let tabs = TabManager.Tab.allCases
    @State private var tabManager = TabManager()
    @State private var subscriptionStore = SubscriptionStore(catalog: .production)
    @State private var cleanupWorkspace = CleanupWorkspaceModel()
    @AppStorage("gridColumns") private var gridColumns = GridConfiguration.current.defaultColumns
    @AppStorage("sensitivity") private var sensitivityRaw = SensitivityLevel.medium.rawValue
#if DEBUG
    @AppStorage(PremiumFeature.unlimitedScans.debugOverrideDefaultsKey)
    private var debugUnlockUnlimitedRescans = false
    @AppStorage(PremiumFeature.screenshotCleanup.debugOverrideDefaultsKey)
    private var debugUnlockScreenshotCleanup = false
    @AppStorage(PremiumFeature.blurredPhotoCleanup.debugOverrideDefaultsKey)
    private var debugUnlockBlurredPhotoCleanup = false
    @AppStorage(PremiumFeature.advancedFilters.debugOverrideDefaultsKey)
    private var debugUnlockAdvancedFilters = false
    @AppStorage(PremiumFeature.batchCleanup.debugOverrideDefaultsKey)
    private var debugUnlockBatchCleanup = false
    @AppStorage(PremiumFeature.cleanupReminderCustomization.debugOverrideDefaultsKey)
    private var debugUnlockCleanupReminders = false
#endif
    private let gridConfiguration = GridConfiguration.current
    private let cleanupReminderManager: any CleanupReminderManaging = CleanupReminderManager(
        preferenceRepository: UserDefaultsCleanupReminderPreferenceRepository()
    )
    
    private var sensitivity: Binding<SensitivityLevel> {
        Binding(
            get: { SensitivityLevel(rawValue: sensitivityRaw) ?? .medium },
            set: { sensitivityRaw = $0.rawValue }
        )
    }

    private var premiumAccess: any PremiumAccessControlling {
#if DEBUG
        DebugPremiumAccessController(base: subscriptionStore)
#else
        subscriptionStore
#endif
    }

    private var hasCleanupReminderCustomizationAccess: Bool {
        premiumAccess.hasAccess(to: .cleanupReminderCustomization)
    }

    private var cleanupReminderTaskID: CleanupReminderTaskID {
        CleanupReminderTaskID(
            scenePhase: scenePhase,
            isPremiumUnlocked: hasCleanupReminderCustomizationAccess
        )
    }
    
    var body: some View {
        // Reading the observable state keeps all injected feature views in sync
        // when StoreKit confirms, restores, or revokes an entitlement.
        let _ = subscriptionStore.entitlementState

        adaptiveTabView
        .tint(.accent)
        .subscriptionLegalLinks(SubscriptionConfiguration.legalLinks)
        .task {
            let clamped = gridConfiguration.clampedColumns(gridColumns)
            if clamped != gridColumns {
                gridColumns = clamped
            }
            await subscriptionStore.start()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await subscriptionStore.refreshEntitlements()
        }
        .task(id: cleanupReminderTaskID) {
            guard scenePhase == .active else { return }
            await resyncCleanupReminder()
        }
        .onDisappear {
            subscriptionStore.stop()
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
    private var adaptiveTabView: some View {
        if #available(iOS 26.0, *) {
            tabView
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabView
        }
    }

    private var tabView: some View {
        TabView(selection: Bindable(tabManager).selectedTab) {
            ForEach(tabs, id: \.self) { tab in
                tabView(for: tab)
                    .tabItem {
                        Label(tab.titleKey, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
    }
    
    @ViewBuilder
    private func tabView(for tab: TabManager.Tab) -> some View {
        switch tab {
        case .scanner:
            ScannerView(
                workspace: cleanupWorkspace,
                gridColumns: Binding(
                    get: { gridConfiguration.clampedColumns(gridColumns) },
                    set: { gridColumns = gridConfiguration.clampedColumns($0) }
                ),
                sensitivity: sensitivity,
                shouldStartScan: Bindable(tabManager).shouldStartScan,
                subscriptionStore: subscriptionStore,
                onOpenCleanup: {
                    tabManager.navigateToCleanup()
                },
                viewModel: ScannerViewModel(
                    workspace: cleanupWorkspace,
                    gridColumns: gridConfiguration.clampedColumns(gridColumns),
                    sensitivity: sensitivity.wrappedValue,
                    premiumAccess: premiumAccess
                )
            )
#if DEBUG
            .id("\(debugUnlockUnlimitedRescans)-\(debugUnlockScreenshotCleanup)-\(debugUnlockBlurredPhotoCleanup)-\(debugUnlockAdvancedFilters)-\(debugUnlockBatchCleanup)")
#endif
        case .cleanup:
            CleanupView(
                workspace: cleanupWorkspace,
                gridColumns: Binding(
                    get: { gridConfiguration.clampedColumns(gridColumns) },
                    set: { gridColumns = gridConfiguration.clampedColumns($0) }
                ),
                sensitivity: sensitivity,
                premiumAccess: premiumAccess,
                subscriptionStore: subscriptionStore,
                onOpenScanner: {
                    tabManager.navigateToScanner()
                },
                onRequestScan: {
                    tabManager.navigateToScanner(andStartScan: true)
                }
            )
        case .settings:
            SettingsView(
                gridColumns: Binding(
                    get: { gridConfiguration.clampedColumns(gridColumns) },
                    set: { gridColumns = gridConfiguration.clampedColumns($0) }
                ),
                sensitivity: sensitivity,
                needsRescan: Bindable(tabManager).needsRescan,
                premiumAccess: premiumAccess,
                subscriptionStore: subscriptionStore,
                viewModel: SettingsViewModel(
                    cleanupReminderManager: cleanupReminderManager
                )
            )
        }
    }

    private func resyncCleanupReminder() async {
        do {
            try await cleanupReminderManager.resync(
                isPremiumUnlocked: hasCleanupReminderCustomizationAccess
            )
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to resync cleanup reminder: \(error.localizedDescription)"))"
            )
        }
    }
}

private struct CleanupReminderTaskID: Equatable {
    let scenePhase: ScenePhase
    let isPremiumUnlocked: Bool
}
