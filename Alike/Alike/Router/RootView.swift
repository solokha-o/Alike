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
import Photos
import PhotoAnalysis
import Purchases
import PurchasesUI
import WidgetSupport

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
            case .welcome(let mode):
                WelcomeView(isCompleted: .init(
                    get: { false },
                    set: { _ in router.completeWelcome() }
                ), mode: mode)
            case .main:
                MainTabView {
                    router.restartAfterDataDeletion()
                }
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
    private let localAppDataDeleter: any LocalAppDataDeleting = LocalAppDataDeletionService()
    private let widgetSnapshotPublisher = WidgetSnapshotPublisher()
    private let photoPermissionManager: any PhotoPermissionManager = PhotoPermissionManagerImpl()
    @Environment(PendingWidgetDestination.self) private var pendingWidgetDestination
    private let onDataDeleted: @MainActor @Sendable () -> Void
    @AppStorage(AppPreferenceKey.sensitivity)
    private var sensitivityRaw = SensitivityLevel.medium.rawValue
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
    private let cleanupReminderManager: any CleanupReminderManaging = CleanupReminderManager(
        preferenceRepository: UserDefaultsCleanupReminderPreferenceRepository()
    )
    @State private var ratingPrompt = RatingPromptCoordinator(
        repository: UserDefaultsRatingPromptHistoryRepository()
    )

    init(onDataDeleted: @escaping @MainActor @Sendable () -> Void) {
        self.onDataDeleted = onDataDeleted
    }
    
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
            await subscriptionStore.start()
        }
        .task {
            // Seed the rating prompt's install-age clock now, not on whatever cleanup
            // happens to be the first eligible one — see
            // `RatingPromptCoordinator.seedInstallAgeOnLaunch`.
            await ratingPrompt.seedInstallAgeOnLaunch()
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
        // One observer for four of the five publish points: a saved scan, a review
        // that moved the session on, and a finished cleanup all show up in the
        // workspace's observable state. Photo access does not — `PhotoPermissionManager`
        // is not observable and the change happens in Settings, outside the app — so it
        // is caught by `scenePhase` in the signature instead, on the return trip. The
        // fifth point, deleting local data, is an explicit call in `onDeleteAllData`
        // below, because by then there is no state left to observe.
        .task(id: widgetSnapshotSignature) {
            widgetSnapshotPublisher.publish(
                workspace: cleanupWorkspace,
                authorization: photoPermissionManager.authorizationStatus,
                isPremium: subscriptionStore.entitlementState.isPremium
            )
        }
        .onChange(of: pendingWidgetDestination.destination, initial: true) {
            followPendingWidgetDestination()
        }
        .alert(AlikeL10n.Rescan.title, isPresented: Bindable(tabManager).needsRescan) {
            Button(AlikeL10n.Rescan.later, role: .cancel) {
                tabManager.dismissRescan()
            }
            Button(AlikeL10n.Rescan.now) {
                tabManager.triggerRescan()
            }
        } message: {
            Text(AlikeL10n.Rescan.message)
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
                        Label(tab.title, systemImage: tab.icon)
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
                sensitivity: sensitivity,
                shouldStartScan: Bindable(tabManager).shouldStartScan,
                subscriptionStore: subscriptionStore,
                onOpenCleanup: {
                    tabManager.navigateToCleanup()
                },
                viewModel: ScannerViewModel(
                    workspace: cleanupWorkspace,
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
                sensitivity: sensitivity,
                premiumAccess: premiumAccess,
                subscriptionStore: subscriptionStore,
                ratingPrompt: ratingPrompt,
                onOpenScanner: {
                    tabManager.navigateToScanner()
                },
                onRequestScan: {
                    tabManager.navigateToScanner(andStartScan: true)
                },
                pendingWidgetEntry: Bindable(tabManager).pendingCleanupEntry
            )
        case .settings:
            SettingsView(
                sensitivity: sensitivity,
                needsRescan: Bindable(tabManager).needsRescan,
                premiumAccess: premiumAccess,
                subscriptionStore: subscriptionStore,
                onDeleteAllData: {
                    await cleanupWorkspace.prepareForDataDeletion()
                    _ = try await cleanupReminderManager.setEnabled(
                        false,
                        isPremiumUnlocked: hasCleanupReminderCustomizationAccess
                    )
                    try await localAppDataDeleter.deleteAllData()
                    // After the wipe, not before: a snapshot published in between would
                    // put the counts the user just deleted back on their home screen.
                    widgetSnapshotPublisher.clear()
                    onDataDeleted()
                },
                onResetBestShotPersonalization: {
                    await cleanupWorkspace.bestShotPersonalizedConfigProvider.reset()
                },
                viewModel: SettingsViewModel(
                    cleanupReminderManager: cleanupReminderManager,
                    ratingPrompt: ratingPrompt
                )
            )
        }
    }

    /// What has to change before the widget's copy of the aggregates is out of date.
    ///
    /// Recomputed from the observable state rather than pushed from inside
    /// `CleanupWorkspaceModel`: the workspace is a shipped package API, and an
    /// observer here keeps the widget additive to it.
    private var widgetSnapshotSignature: WidgetSnapshotSignature {
        WidgetSnapshotSignature(
            scenePhase: scenePhase,
            authorization: photoPermissionManager.authorizationStatus,
            isPremium: subscriptionStore.entitlementState.isPremium,
            // The baseline and its date, not just the in-memory summary: after a cold
            // launch the cached content arrives without a summary, and that restore is
            // exactly when the widget needs republishing.
            hasCompletedScanBaseline: cleanupWorkspace.hasCompletedScanBaseline,
            lastCompletedScanDate: cleanupWorkspace.lastCompletedScanDate,
            lastScanCompletedAt: cleanupWorkspace.lastScanSummary?.completedAt,
            estimatedSavingsBytes: cleanupWorkspace.lastScanSummary?.estimatedSavingsBytes,
            clusterCount: cleanupWorkspace.clusters.count,
            categoryAssetCount: cleanupWorkspace.cleanupCategories.reduce(0) { $0 + $1.assetCount },
            reviewedClusters: cleanupWorkspace.activeCleanupSession?.reviewedClusters,
            // Opening a group without deciding on it is what turns "scanned" into
            // "reviewing" on the widget, and it moves no other field here.
            inReviewClusters: cleanupWorkspace.sessionProgress().inReviewCount,
            sessionUpdatedAt: cleanupWorkspace.activeCleanupSession?.updatedAt,
            shouldShowRescanPrompt: cleanupWorkspace.shouldShowRescanPrompt
        )
    }

    /// Acts on a widget tap once the main screen is the one on screen.
    ///
    /// Every destination still lands on the cleanup tab; the category-specific ones now
    /// also say *where* in it. They do not deep-link past the Premium gate: the entry is
    /// handed to `CleanupView`, which resolves it through `openCategory` — the one place
    /// that checks entitlement and sends a locked category to its paywall. The widget
    /// names a destination; it does not get to open one.
    ///
    /// `.resumeReview` names the unfinished review, not a group: which group that is
    /// gets decided against the live workspace, not against a snapshot that may be a
    /// day old, and `CleanupView` answers it with `cleanupEntryCluster()` once the
    /// content has loaded. A review finished since the tap lands on the root.
    private func followPendingWidgetDestination() {
        guard let destination = pendingWidgetDestination.consume() else { return }

        switch destination {
        case .cleanup:
            tabManager.navigateToCleanup()
        case .resumeReview:
            tabManager.navigateToCleanup(entry: .resumeReview)
        case .similarPhotos:
            tabManager.navigateToCleanup(entry: .similarPhotos)
        case .screenshots:
            tabManager.navigateToCleanup(entry: .category(.screenshots))
        case .blurredPhotos:
            tabManager.navigateToCleanup(entry: .category(.blurredPhotos))
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

/// The inputs that decide what the widget shows, as one value `task(id:)` can compare.
private struct WidgetSnapshotSignature: Equatable {
    let scenePhase: ScenePhase
    let authorization: PHAuthorizationStatus
    let isPremium: Bool
    let hasCompletedScanBaseline: Bool
    let lastCompletedScanDate: Date?
    let lastScanCompletedAt: Date?
    let estimatedSavingsBytes: Int64?
    let clusterCount: Int
    let categoryAssetCount: Int
    let reviewedClusters: Int?
    let inReviewClusters: Int
    let sessionUpdatedAt: Date?
    let shouldShowRescanPrompt: Bool
}

private struct CleanupReminderTaskID: Equatable {
    let scenePhase: ScenePhase
    let isPremiumUnlocked: Bool
}
