import SwiftUI
import Photos
import StoreKit
import Core
import DesignSystem
import NavigationKit
import PhotoAnalysis
import Purchases
import PurchasesUI

private enum CleanupRoute: Hashable {
    case cluster(PhotoCluster)
    case history
}

private struct PresentedCleanupCategory: Identifiable {
    let kind: CleanupCategoryKind
    let assets: [PHAsset]
    var id: CleanupCategoryKind { kind }
}

/// The review-focused home for results produced by ``CleanupWorkspaceModel``.
/// Scanner owns starting scans and entitlement admission; Cleanup only presents
/// the durable workspace and routes the user to an explicit rescan action.
///
/// The screens a group or a category opens come from the host through
/// `clusterDestination` and `screenshotDestination`, so this package does not depend
/// on the package that implements them. Cleanup still owns how they open: a push for a
/// group, a sheet the user cannot swipe away for a category.
public struct CleanupView<ClusterDestination: View, ScreenshotDestination: View>: View {
    private enum Constants {
        // Computed: a generic type cannot hold static stored properties.
        static var reconciliationDismissalDelay: Duration { .milliseconds(500) }
        /// Lets the success banner land before the system review sheet takes over.
        static var ratingPromptDelay: Duration { .milliseconds(1_500) }
    }

    private let workspace: CleanupWorkspaceModel
    @Binding private var sensitivity: SensitivityLevel
    private let premiumAccess: any PremiumAccessControlling
    private let subscriptionStore: SubscriptionStore?
    private let ratingPrompt: RatingPromptCoordinator
    private let onOpenScanner: @MainActor @Sendable () -> Void
    private let onRequestScan: @MainActor @Sendable () -> Void
    @Binding private var pendingWidgetEntry: CleanupWidgetEntry?
    private let clusterDestination: (CleanupClusterDestinationContext) -> ClusterDestination
    private let screenshotDestination: (CleanupCategoryDestinationContext) -> ScreenshotDestination

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @PhotoGridColumnPreference private var selectedGridColumnCount
    @State private var controls = CleanupClusterControls()
    @State private var isControlsPresented = false
    @State private var presentedCategory: PresentedCleanupCategory?
    @State private var presentedPaywall: PremiumFeature?
    @State private var categoryError: String?
    @State private var dismissedReconciliationID: UUID?
    @State private var arrangement = CleanupClusterArrangement()
    @State private var scrollAnchorID: String?

    public init(
        workspace: CleanupWorkspaceModel,
        sensitivity: Binding<SensitivityLevel>,
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        subscriptionStore: SubscriptionStore? = nil,
        ratingPrompt: RatingPromptCoordinator,
        onOpenScanner: @escaping @MainActor @Sendable () -> Void,
        onRequestScan: @escaping @MainActor @Sendable () -> Void,
        // Defaulted: every existing call site stays valid, and a host that has no
        // widget routing to feed in does not have to know this parameter exists.
        pendingWidgetEntry: Binding<CleanupWidgetEntry?> = .constant(nil),
        @ViewBuilder clusterDestination: @escaping (CleanupClusterDestinationContext) -> ClusterDestination,
        @ViewBuilder screenshotDestination: @escaping (CleanupCategoryDestinationContext) -> ScreenshotDestination
    ) {
        self.workspace = workspace
        self._sensitivity = sensitivity
        self.premiumAccess = premiumAccess
        self.subscriptionStore = subscriptionStore
        self.ratingPrompt = ratingPrompt
        self.onOpenScanner = onOpenScanner
        self.onRequestScan = onRequestScan
        self._pendingWidgetEntry = pendingWidgetEntry
        self.clusterDestination = clusterDestination
        self.screenshotDestination = screenshotDestination
    }

    public var body: some View {
        RoutedNavigationStack { router in
            mainContent(router: router)
        } destination: { route, _ in
            destination(for: route)
        }
        .task {
            await workspace.loadCachedContent()
            _ = await workspace.checkForGalleryChanges()
        }
        .sheet(item: $presentedCategory) { category in
            RoutedNavigationStack {
                screenshotDestination(
                    CleanupCategoryDestinationContext(
                        kind: category.kind,
                        assets: category.assets,
                        onCleanupCompleted: reconcile
                    )
                )
            }
            .interactiveDismissDisabled()
        }
        .sheet(item: $presentedPaywall) { feature in
            SubscriptionPaywallView(context: paywallContext(for: feature), store: subscriptionStore)
        }
        .sheet(isPresented: $isControlsPresented) {
            CleanupClusterControlsSheet(
                controls: $controls,
                isAdvancedFilteringLocked: !premiumAccess.hasAccess(to: .advancedFilters),
                onRequestAdvancedFilters: {
                    isControlsPresented = false
                    presentedPaywall = .advancedFilters
                }
            )
        }
        .alert(CleanupL10n.Main.couldntOpenCleanupCategory, isPresented: errorBinding) {
            Button(CleanupL10n.Main.ok, role: .cancel) { categoryError = nil }
        } message: {
            Text(categoryError ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { categoryError != nil }, set: { if !$0 { categoryError = nil } })
    }

    @ViewBuilder
    private func destination(for route: CleanupRoute) -> some View {
        switch route {
        case .cluster(let cluster):
            clusterDestination(
                CleanupClusterDestinationContext(
                    cluster: cluster,
                    onReviewStateChanged: { Task { await workspace.reloadReviewState() } },
                    onCleanupCompleted: reconcile
                )
            )
        case .history:
            CleanupHistoryView(
                repository: workspace.cleanupHistoryRepository
            )
        }
    }

    @ViewBuilder
    private func mainContent(router: StackRouter<CleanupRoute>) -> some View {
        ScrollView {
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer(spacing: Spacing.medium) {
                    cleanupStack(router: router)
                }
            } else {
                cleanupStack(router: router)
            }
        }
        .scrollPosition(id: $scrollAnchorID)
        .overlay(alignment: .top) {
            reconciliationOverlay
                .animation(
                    accessibilityReduceMotion ? nil : .appSmooth,
                    value: workspace.reconciliationState
                )
        }
        .navigationTitle(Text(CleanupL10n.Main.cleanup))
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .toolbar { cleanupToolbar }
        .task(id: terminalReconciliationState) {
            await requestRatingIfEligible(for: terminalReconciliationState)
        }
        .onAppear(perform: refreshArrangement)
        .onChange(of: controls) { _, _ in refreshArrangement() }
        .onChange(of: workspace.clusterIdentityKey) { _, _ in refreshArrangement() }
        .onChange(of: premiumAccess.hasAccess(to: .advancedFilters)) { _, _ in refreshArrangement() }
        // Both, not just the first: on a cold launch the widget's intent is already set
        // before `loadCachedContent()` returns, and acting on it then would look up a
        // category in an empty list. The second observer is what picks it back up.
        //
        // Applied after the `refreshArrangement` observers above so the arrangement is
        // already current when the scroll anchor is read off it.
        .onChange(of: pendingWidgetEntry, initial: true) { _, _ in followPendingWidgetEntry(router: router) }
        .onChange(of: isContentLoaded) { _, _ in followPendingWidgetEntry(router: router) }
        // A deferred entry is picked back up when whatever held it resolves: the sheet
        // on screen closes, or StoreKit says what the account is entitled to.
        .onChange(of: isScreenOwned) { _, _ in followPendingWidgetEntry(router: router) }
        .onChange(of: premiumAccess.isEntitlementSettled) { _, _ in followPendingWidgetEntry(router: router) }
        // A deferred tap lives for one foreground session: a paywall surfacing on a
        // later resume, long after the tap, would read as the app acting on its own.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { pendingWidgetEntry = nil }
        }
    }

    private func cleanupStack(router: StackRouter<CleanupRoute>) -> some View {
        VStack(spacing: Spacing.medium) {
            CleanupPersistentBanners(
                scanOperation: workspace.scanOperation,
                showsRescanPrompt: workspace.shouldShowRescanPrompt,
                onRequestScan: onRequestScan
            )
            .animation(.appSmooth, value: displayedScanOperation)
            switch workspace.contentState {
            case .notLoaded:
                ProgressView().padding(.top, Spacing.xxLarge)
            case .neverScanned:
                neverScanned
            case .unavailable(let message):
                unavailable(message)
            case .content:
                cleanupContent(router: router)
            }
        }
        .padding(Spacing.medium)
    }

    @ViewBuilder
    private var reconciliationOverlay: some View {
        if let state = terminalReconciliationState, state.record.id != dismissedReconciliationID {
            CleanupReconciliationBanner(
                state: state,
                onRequestScan: onRequestScan,
                onDismiss: dismissReconciliation
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.medium)
            .padding(.top, Spacing.xSmall)
            .transition(
                accessibilityReduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
            .zIndex(1)
            .task(id: state) {
                await autoDismissReconciliationSuccess(state)
            }
        }
    }

    private var terminalReconciliationState: CleanupReconciliationState? {
        CleanupPresentation.terminalReconciliationState(workspace.reconciliationState)
    }

    private var displayedScanOperation: ScanOperationState? {
        CleanupPresentation.displayedScanOperation(workspace.scanOperation)
    }

    /// `true` while any other surface owns the screen, so the review sheet never lands on
    /// top of a paywall, a sheet, an alert, or a running scan.
    private var isRatingPromptBlocked: Bool {
        CleanupPresentation.isRatingPromptBlocked(
            isScreenOwned: isScreenOwned,
            scanOperation: workspace.scanOperation,
            isSceneActive: scenePhase == .active
        )
    }

    /// Asks for an App Store review after a cleanup that actually removed photos.
    ///
    /// The request is fire-and-forget: iOS decides whether anything is shown, and the
    /// result is deliberately not observed.
    private func requestRatingIfEligible(for state: CleanupReconciliationState?) async {
        guard case .success(let record) = state else { return }

        do {
            try await Task.sleep(for: Constants.ratingPromptDelay)
        } catch {
            return
        }

        guard
            await ratingPrompt.requestReviewIfEligible(
                after: record,
                isBusy: { isRatingPromptBlocked }
            )
        else { return }

        // Recheck live state one more time: the coordinator's own recheck covers the await
        // it awaits internally, but nothing else has run between its return and this call.
        guard !isRatingPromptBlocked else { return }

        requestReview()
    }

    private func autoDismissReconciliationSuccess(_ state: CleanupReconciliationState) async {
        guard case .success(let record) = state else { return }

        do {
            try await Task.sleep(for: .seconds(4))
        } catch {
            return
        }

        guard workspace.reconciliationState == .success(record) else { return }
        dismissReconciliation(record.id)
    }

    private func dismissReconciliation(_ recordID: UUID) {
        withAnimation(accessibilityReduceMotion ? nil : .appSmooth) {
            dismissedReconciliationID = recordID
        }
    }

    private var neverScanned: some View {
        ContentUnavailableView {
            Label(CleanupL10n.Main.scanYourLibraryFirst, systemImage: "viewfinder")
        } description: {
            Text(CleanupL10n.Main.startScanFindSimilarPhotos)
        } actions: {
            Button(CleanupL10n.Main.goToScanner, action: onOpenScanner)
                .cleanupGlassButton(isProminent: true)
        }
        .frame(minHeight: 360)
    }

    private func unavailable(_ message: String) -> some View {
        ContentUnavailableView {
            Label(CleanupL10n.Main.cleanupUnavailable, systemImage: "exclamationmark.triangle")
        } description: { Text(message) } actions: {
            Button(CleanupL10n.Main.goToScanner, action: onOpenScanner)
                .cleanupGlassButton()
        }
        .frame(minHeight: 360)
    }

    @ViewBuilder
    private func cleanupContent(router: StackRouter<CleanupRoute>) -> some View {
        if arrangement.hasAnyCluster {
            let entry = workspace.cleanupEntryCluster()
            CleanupProgressCard(
                progress: workspace.sessionProgress(),
                onContinue: entry.map { cluster in { router.push(.cluster(cluster)) } },
                onOpenHistory: { router.push(.history) }
            )
        }
        if !workspace.cleanupCategories.isEmpty {
            CleanupCategoriesCard(categories: workspace.cleanupCategories, isLocked: { !premiumAccess.hasAccess(to: $0.premiumFeature) }, onTap: openCategory)
        }
        if CleanupPresentation.showsNoOpportunities(
            hasAnyCluster: arrangement.hasAnyCluster,
            hasCategories: !workspace.cleanupCategories.isEmpty
        ) {
            ContentUnavailableView {
                Label(CleanupL10n.Main.noCleanupOpportunities, systemImage: "checkmark.seal")
            } description: { Text(CleanupL10n.Main.latestScanDidNotFind) }
            .padding(.top, Spacing.xxLarge)
        } else if arrangement.isEmptyAfterFiltering {
            ContentUnavailableView {
                Label(CleanupL10n.Main.noClustersMatchTheseControls, systemImage: "line.3.horizontal.decrease.circle")
            } description: { Text(CleanupL10n.Main.tryChangingFiltersResettingControls) } actions: {
                Button(CleanupL10n.Main.resetControls) { controls = CleanupClusterControls() }
                    .cleanupGlassButton()
            }
        } else {
            if !arrangement.needsReview.isEmpty {
                CleanupClusterSection(title: CleanupL10n.Main.needsReview, subtitle: CleanupL10n.Main.newChangedClustersAfterLatest, clusters: arrangement.needsReview, gridColumns: selectedGridColumnCount, workspace: workspace) { router.push(.cluster($0)) }
            }
            if !arrangement.remaining.isEmpty {
                CleanupClusterSection(title: CleanupL10n.Main.allClusters, subtitle: CleanupL10n.Main.everythingElseStillAvailableCleanup, clusters: arrangement.remaining, gridColumns: selectedGridColumnCount, workspace: workspace) { router.push(.cluster($0)) }
            }
        }
    }

    @ToolbarContentBuilder
    private var cleanupToolbar: some ToolbarContent {
#if os(iOS)
        if #available(iOS 27.0, *) {
            overflowCleanupToolbar
        } else {
            if !workspace.clusters.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { columnsMenu }
                ToolbarItem(placement: .topBarTrailing) { controlsButton }
            }
            if workspace.hasCompletedScanBaseline {
                ToolbarItem(placement: .topBarTrailing) { rescanButton }
            }
        }
#else
        if !workspace.clusters.isEmpty {
            ToolbarItem { columnsMenu }
            ToolbarItem { controlsButton }
        }
        if workspace.hasCompletedScanBaseline {
            ToolbarItem { rescanButton }
        }
#endif
    }

#if os(iOS)
    /// Three icons next to a large title clip on a 375 pt screen at large
    /// Dynamic Type. Rescan is the screen's main action, so it stays pinned;
    /// the grid and filter options fold into the system overflow menu.
    @available(iOS 27.0, *)
    @ToolbarContentBuilder
    private var overflowCleanupToolbar: some ToolbarContent {
        if workspace.hasCompletedScanBaseline {
            ToolbarItem(placement: .topBarPinnedTrailing) { rescanButton }
                .visibilityPriority(.high)
        }
        if !workspace.clusters.isEmpty {
            ToolbarOverflowMenu {
                PhotoGridColumnsPicker()
                Button { isControlsPresented = true } label: {
                    Label(
                        CleanupL10n.Main.filterAndSort,
                        systemImage: CleanupPresentation.controlsIconName(isDefault: controls.isDefault)
                    )
                }
            }
            .visibilityPriority(.low)
        }
    }
#endif

    private var columnsMenu: some View {
        PhotoGridColumnsMenu()
    }

    private var controlsButton: some View {
        Button { isControlsPresented = true } label: {
            Image(systemName: CleanupPresentation.controlsIconName(isDefault: controls.isDefault))
        }
        .accessibilityLabel(Text(CleanupL10n.Main.filterAndSortClusters))
    }

    private var rescanButton: some View {
        Button(action: onRequestScan) { Image(systemName: "arrow.clockwise") }
            .accessibilityLabel(Text(CleanupL10n.Main.rescanPhotos))
    }

    /// Whether there is anything loaded to route a widget tap against.
    ///
    /// A `Bool` rather than `contentState` itself: that value carries the whole
    /// `CleanupWorkspaceContent`, and an `onChange` on it would deep-compare a full
    /// library on every workspace mutation. `refreshArrangement` keeps its distance
    /// from it for the same reason.
    private var isContentLoaded: Bool {
        workspace.contentState != .notLoaded
    }

    /// Whether a sheet or alert of this screen is up, so a widget entry waits for it.
    ///
    /// Re-assigning an `Identifiable` sheet item while its sheet is up does not reliably
    /// swap it, and a list or paywall the user is in is not something a home-screen tap
    /// should replace.
    private var isScreenOwned: Bool {
        presentedCategory != nil
            || presentedPaywall != nil
            || isControlsPresented
            || categoryError != nil
    }

    /// Acts on a place a widget tap asked for, once there is something to act against.
    ///
    /// Deliberately routed through `openCategory` rather than presenting the category
    /// itself: that function holds the Premium gate, and a second way into a gated list
    /// would be a way around the paywall. A locked category reaches its paywall here by
    /// exactly the path an in-app tap takes.
    ///
    /// `router` is the stack this screen is hosted in, so a resume can push the group
    /// the workspace says the review stopped at instead of leaving the user on the root
    /// to press Continue a second time.
    private func followPendingWidgetEntry(router: StackRouter<CleanupRoute>) {
        guard let entry = pendingWidgetEntry else { return }

        // Still restoring. The intent is kept, and the `isContentLoaded` observer brings
        // us back here once the categories and clusters are actually loaded.
        guard isContentLoaded else { return }

        // Resolved against the workspace as it is now, so an entry that waited out a
        // sheet sees whatever that sheet changed.
        let resolution = entry.resolution(
            categories: workspace.cleanupCategories,
            orderedClusterIDs: arrangement.orderedIDs,
            resumeCluster: workspace.cleanupEntryCluster()
        )

        // Kept, not dropped: the `isScreenOwned` and entitlement observers bring us
        // back once a sheet closes or StoreKit answers. See `mustDefer` for why each.
        guard !CleanupWidgetEntry.mustDefer(
            resolution,
            isScreenOwned: isScreenOwned,
            isEntitlementSettled: premiumAccess.isEntitlementSettled,
            hasAccess: { premiumAccess.hasAccess(to: $0.premiumFeature) }
        ) else { return }

        pendingWidgetEntry = nil

        switch resolution {
        case let .openCategory(summary):
            openCategory(summary)
        case let .openCluster(cluster):
            // The same push `CleanupProgressCard`'s Continue makes. The widget names the
            // intent; the destination is still the app's own answer to "where was I".
            router.push(.cluster(cluster))
        case let .scrollTo(id):
            scrollAnchorID = id
        case .stayOnRoot:
            break
        }
    }

    private func openCategory(_ category: CleanupCategorySummary) {
        guard premiumAccess.hasAccess(to: category.kind.premiumFeature) else {
            presentedPaywall = category.kind.premiumFeature
            return
        }
        Task {
            do {
                let assets = try await workspace.loadAssets(for: category.kind)
                presentedCategory = PresentedCleanupCategory(kind: category.kind, assets: assets)
            } catch {
                categoryError = error.localizedDescription
            }
        }
    }

    private func reconcile(_ record: CleanupCompletionRecord) {
        let selectedSensitivity = sensitivity
        Task {
            try? await Task.sleep(for: Constants.reconciliationDismissalDelay)
            await workspace.reconcile(after: record, sensitivity: selectedSensitivity)
        }
    }

    private func paywallContext(for feature: PremiumFeature) -> PremiumSurfaceContext {
        CleanupPresentation.paywallContext(for: feature, categories: workspace.cleanupCategories)
    }

    /// Re-derives the displayed cluster order and sectioning.
    ///
    /// Deliberately not driven by `workspace.reviewStates`: `ClusterDetailsView`
    /// reports review progress back while it is still pushed, and reordering the
    /// grid then would leave the restored scroll offset pointing at a different
    /// row. Cards still show live review badges because they read status from the
    /// workspace directly.
    private func refreshArrangement() {
        let updated = CleanupClusterArrangement.make(
            clusters: workspace.clusters,
            controls: controls,
            appliesAdvancedFilters: premiumAccess.hasAccess(to: .advancedFilters),
            reviewStatus: { workspace.reviewStatus(for: $0) },
            estimatedSavings: { workspace.reviewState(for: $0)?.estimatedSavingsBytes ?? 0 }
        )
        scrollAnchorID = updated.preservedAnchor(scrollAnchorID, replacing: arrangement)
        arrangement = updated
    }
}

// The destinations are stubs: the real group and category screens live in a package
// Cleanup does not depend on, and the app builds them. Gated like the Details preview,
// so nothing preview-only reaches a Release build.
#if DEBUG
#Preview("Cleanup") {
    CleanupView(
        workspace: CleanupWorkspaceModel(),
        sensitivity: .constant(.medium),
        ratingPrompt: RatingPromptCoordinator(),
        onOpenScanner: {},
        onRequestScan: {}
    ) { context in
        Text(verbatim: "Group: \(context.cluster.assets.count) photos")
    } screenshotDestination: { context in
        Text(verbatim: "Category: \(context.kind.rawValue), \(context.assets.count) photos")
    }
}
#endif
