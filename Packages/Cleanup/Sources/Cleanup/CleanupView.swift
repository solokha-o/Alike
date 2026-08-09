import SwiftUI
import Photos
import StoreKit
import Core
import DesignSystem
import Details
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

fileprivate enum CleanupGlassBadgeShape {
    case capsule
    case circle
}

private struct CleanupGlassSurfaceModifier: ViewModifier {
    let isInteractive: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if isInteractive {
                content.glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content.background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

fileprivate struct CleanupGlassBadgeModifier: ViewModifier {
    let shape: CleanupGlassBadgeShape

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            switch shape {
            case .capsule:
                content.glassEffect(.regular, in: .capsule)
            case .circle:
                content.glassEffect(.regular, in: .circle)
            }
        } else {
            switch shape {
            case .capsule:
                content.background(.regularMaterial, in: Capsule())
            case .circle:
                content.background(.regularMaterial, in: Circle())
            }
        }
    }
}

private struct CleanupGlassButtonStyle: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if isProminent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if isProminent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func cleanupGlassSurface(
        isInteractive: Bool = false,
        cornerRadius: CGFloat = CornerRadius.medium
    ) -> some View {
        modifier(
            CleanupGlassSurfaceModifier(
                isInteractive: isInteractive,
                cornerRadius: cornerRadius
            )
        )
    }

    fileprivate func cleanupGlassBadge(_ shape: CleanupGlassBadgeShape = .capsule) -> some View {
        modifier(CleanupGlassBadgeModifier(shape: shape))
    }

    func cleanupGlassButton(isProminent: Bool = false) -> some View {
        modifier(CleanupGlassButtonStyle(isProminent: isProminent))
    }
}

/// The review-focused home for results produced by ``CleanupWorkspaceModel``.
/// Scanner owns starting scans and entitlement admission; Cleanup only presents
/// the durable workspace and routes the user to an explicit rescan action.
public struct CleanupView: View {
    private enum Constants {
        static let reconciliationDismissalDelay = Duration.milliseconds(500)
        /// Lets the success banner land before the system review sheet takes over.
        static let ratingPromptDelay = Duration.milliseconds(1_500)
    }

    private let workspace: CleanupWorkspaceModel
    @Binding private var sensitivity: SensitivityLevel
    private let premiumAccess: any PremiumAccessControlling
    private let subscriptionStore: SubscriptionStore?
    private let ratingPrompt: RatingPromptCoordinator
    private let onOpenScanner: @MainActor @Sendable () -> Void
    private let onRequestScan: @MainActor @Sendable () -> Void

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
        onRequestScan: @escaping @MainActor @Sendable () -> Void
    ) {
        self.workspace = workspace
        self._sensitivity = sensitivity
        self.premiumAccess = premiumAccess
        self.subscriptionStore = subscriptionStore
        self.ratingPrompt = ratingPrompt
        self.onOpenScanner = onOpenScanner
        self.onRequestScan = onRequestScan
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
                ScreenshotCleanupView(
                    assets: category.assets,
                    sourceCategory: category.kind,
                    cleanupService: workspace.cleanupService,
                    cleanupHistoryRepository: workspace.cleanupHistoryRepository,
                    premiumAccess: premiumAccess,
                    subscriptionStore: subscriptionStore,
                    openSettingsAction: {
                        PhotoPermissionManagerImpl().openSettings()
                    },
                    onCleanupCompleted: reconcile
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
            ClusterDetailsView(
                cluster: cluster,
                cleanupService: workspace.cleanupService,
                cleanupHistoryRepository: workspace.cleanupHistoryRepository,
                premiumAccess: premiumAccess,
                subscriptionStore: subscriptionStore,
                openSettingsAction: {
                    PhotoPermissionManagerImpl().openSettings()
                },
                onReviewStateChanged: { Task { await workspace.reloadReviewState() } },
                onCleanupCompleted: reconcile
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
    }

    private func cleanupStack(router: StackRouter<CleanupRoute>) -> some View {
        VStack(spacing: Spacing.medium) {
            persistentBanners
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
    private var persistentBanners: some View {
        if case .scanning(let progress, .userInitiated) = workspace.scanOperation {
            CleanupStatusBanner(
                icon: "arrow.triangle.2.circlepath",
                title: CleanupL10n.Main.refreshingCleanup,
                message: String(format: CleanupL10n.Main.scanningYourLibrary, Int(progress * 100)),
                showsProgress: true,
                progress: progress
            )
        } else if case .failed(let message, .userInitiated) = workspace.scanOperation {
            CleanupStatusBanner(
                icon: "exclamationmark.triangle.fill",
                title: CleanupL10n.Main.scanFailed,
                message: message
            )
        }
        if workspace.shouldShowRescanPrompt {
            CleanupStatusBanner(
                icon: "photo.badge.arrow.down",
                title: CleanupL10n.Main.yourLibraryChanged,
                message: CleanupL10n.Main.runNewScanRefreshCleanup,
                actionTitle: CleanupL10n.Main.rescan,
                action: onRequestScan
            )
        }
    }

    @ViewBuilder
    private var reconciliationOverlay: some View {
        if let state = terminalReconciliationState, state.record.id != dismissedReconciliationID {
            reconciliationBanner(state)
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

    @ViewBuilder
    private func reconciliationBanner(_ state: CleanupReconciliationState) -> some View {
        switch state {
        case .refreshing:
            EmptyView()
        case .success(let record):
            CleanupStatusBanner(
                icon: "checkmark.circle.fill",
                title: String(format: CleanupL10n.Main.photosMovedToRecentlyDeleted, record.deletedCount),
                message: CleanupL10n.Main.cleanupResultsUpDate,
                dismiss: { dismissReconciliation(record.id) }
            )
        case .failed(let record, let message):
            CleanupStatusBanner(
                icon: "exclamationmark.triangle.fill",
                title: CleanupL10n.Main.refreshRequired,
                message: message,
                actionTitle: CleanupL10n.Main.rescan,
                action: onRequestScan,
                dismiss: { dismissReconciliation(record.id) }
            )
        }
    }

    private var terminalReconciliationState: CleanupReconciliationState? {
        guard let state = workspace.reconciliationState else { return nil }
        if case .refreshing = state { return nil }
        return state
    }

    private var displayedScanOperation: ScanOperationState? {
        switch workspace.scanOperation {
        case .scanning(_, .userInitiated), .failed(_, .userInitiated):
            workspace.scanOperation
        case .idle, .scanning(_, .reconciliation), .failed(_, .reconciliation):
            nil
        }
    }

    /// `true` while any other surface owns the screen, so the review sheet never lands on
    /// top of a paywall, a sheet, an alert, or a running scan.
    private var isRatingPromptBlocked: Bool {
        presentedCategory != nil
            || presentedPaywall != nil
            || isControlsPresented
            || categoryError != nil
            || workspace.scanOperation != .idle
            || scenePhase != .active
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
        if !arrangement.hasAnyCluster && workspace.cleanupCategories.isEmpty {
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
        if !workspace.clusters.isEmpty {
            ToolbarItem(placement: .topBarTrailing) { columnsMenu }
            ToolbarItem(placement: .topBarTrailing) { controlsButton }
        }
        if workspace.hasCompletedScanBaseline {
            ToolbarItem(placement: .topBarTrailing) { rescanButton }
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

    private var columnsMenu: some View {
        PhotoGridColumnsMenu()
    }

    private var controlsButton: some View {
        Button { isControlsPresented = true } label: {
            Image(systemName: controls.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel(Text(CleanupL10n.Main.filterAndSortClusters))
    }

    private var rescanButton: some View {
        Button(action: onRequestScan) { Image(systemName: "arrow.clockwise") }
            .accessibilityLabel(Text(CleanupL10n.Main.rescanPhotos))
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
        if let kind = feature.categoryKind,
           let category = workspace.cleanupCategories.first(where: { $0.kind == kind }) {
            return .smartCategory(
                feature: feature,
                title: kind.presentation.title,
                estimatedSavings: ByteCountFormatter.string(fromByteCount: category.estimatedSavingsBytes, countStyle: .file)
            )
        }
        return .feature(feature)
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

public enum CleanupClusterSort: String, CaseIterable, Sendable {
    case newest
    case largestCleanupOpportunity
    case largestCluster
    case similarity
    case reviewStatus

    var title: String {
        switch self {
        case .newest:
            CleanupL10n.Main.newest
        case .largestCleanupOpportunity:
            CleanupL10n.Main.mostSpaceToSave
        case .largestCluster:
            CleanupL10n.Main.largestCluster
        case .similarity:
            CleanupL10n.Main.highestSimilarity
        case .reviewStatus:
            CleanupL10n.Main.reviewStatus
        }
    }
}

public enum CleanupReviewFilter: String, CaseIterable, Sendable {
    case all
    case needsReview
    case inReview
    case reviewed

    /// `needsReview` covers everything the user has not finished reviewing: clusters
    /// never opened (`notReviewed`) as well as clusters a rescan changed (`needsReReview`).
    public func matches(_ status: ClusterReviewStatus) -> Bool {
        switch self {
        case .all: true
        case .needsReview: status == .notReviewed || status == .needsReReview
        case .inReview: status == .inReview
        case .reviewed: status == .reviewed
        }
    }

    var title: String {
        switch self {
        case .all:
            CleanupL10n.Main.allReviewStates
        case .needsReview:
            CleanupL10n.Main.needsReview
        case .inReview:
            CleanupL10n.Main.inReview
        case .reviewed:
            CleanupL10n.Main.reviewed
        }
    }
}

public enum CleanupMinimumClusterSize: Int, CaseIterable, Sendable {
    case any = 0
    case two = 2
    case three = 3
    case five = 5
    case ten = 10
    case twenty = 20

    var title: String {
        self == .any
            ? CleanupL10n.Main.anySize
            : String(format: CleanupL10n.Main.orMorePhotos, rawValue)
    }
}
public struct CleanupClusterControls: Equatable, Sendable {
    public var sort: CleanupClusterSort = .newest
    public var reviewFilter: CleanupReviewFilter = .all
    public var minimumClusterSize: CleanupMinimumClusterSize = .any
    public var favoritesOnly = false
    public var isDefault: Bool { self == Self() }

    public init() {}

    public func matches(_ cluster: PhotoCluster, reviewStatus: ClusterReviewStatus) -> Bool {
        reviewFilter.matches(reviewStatus)
            && cluster.count >= minimumClusterSize.rawValue
            && (!favoritesOnly || cluster.assets.contains(where: \.isFavorite))
    }
}

private struct CleanupClusterControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var controls: CleanupClusterControls
    let isAdvancedFilteringLocked: Bool
    let onRequestAdvancedFilters: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(CleanupL10n.Main.sortBy) {
                    Picker(CleanupL10n.Main.sortOrder, selection: $controls.sort) {
                        ForEach(CleanupClusterSort.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                }

                Section(CleanupL10n.Main.filterBy) {
                    if isAdvancedFilteringLocked {
                        Button(action: onRequestAdvancedFilters) {
                            Label(CleanupL10n.Main.unlockAdvancedFilters, systemImage: "lock.fill")
                        }
                    } else {
                        Picker(CleanupL10n.Main.reviewStatus, selection: $controls.reviewFilter) {
                            ForEach(CleanupReviewFilter.allCases, id: \.self) {
                                Text($0.title).tag($0)
                            }
                        }
                        Picker(CleanupL10n.Main.minimumClusterSize, selection: $controls.minimumClusterSize) {
                            ForEach(CleanupMinimumClusterSize.allCases, id: \.self) {
                                Text($0.title).tag($0)
                            }
                        }
                        Toggle(CleanupL10n.Main.favoritesOnly, isOn: $controls.favoritesOnly)
                    }
                }

                Section {
                    Button(CleanupL10n.Main.resetControls, role: .destructive) {
                        controls = CleanupClusterControls()
                    }
                    .disabled(controls.isDefault)
                }
            }
            .navigationTitle(Text(CleanupL10n.Main.filterAndSort))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(CleanupL10n.Main.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CleanupProgressCard: View {
    let progress: CleanupSessionProgress
    let onContinue: (() -> Void)?
    let onOpenHistory: () -> Void
    private let metricColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .top, spacing: Spacing.small) {
                leadingRow

                Button(action: onOpenHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .frame(width: 22, height: 22)
                }
                .cleanupGlassButton()
                .controlSize(.small)
                .accessibilityLabel(Text(CleanupL10n.Main.cleanupHistory))
            }

            ProgressView(value: progress.reviewedRatio)
            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: Spacing.small) {
                metric("\(progress.reviewedCount)/\(progress.totalClusters)", CleanupL10n.Main.reviewed)
                metric("\(progress.remainingClusters)", CleanupL10n.Main.remaining)
                metric("\(progress.totalSelectedItems)", CleanupL10n.Main.selected)
                metric(ByteCountFormatter.string(fromByteCount: progress.reviewedSavingsBytes, countStyle: .file), CleanupL10n.Main.estimatedSavings)
            }
        }
        .padding(Spacing.medium)
        .cleanupGlassSurface()
    }

    @ViewBuilder
    private var leadingRow: some View {
        if let onContinue {
            Button(action: onContinue) {
                summary(
                    title: CleanupL10n.Main.continueReview,
                    subtitle: CleanupL10n.Main.pickUpWhereLeftOff,
                    iconName: "arrow.right.circle.fill",
                    iconColor: Color.accent
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(continueAccessibilityLabel))
            .accessibilityHint(Text(CleanupL10n.Main.openNextClusterContinueCleanup))
        } else {
            summary(
                title: CleanupL10n.Main.allClustersReviewed,
                subtitle: CleanupL10n.Main.nothingLeftReviewRightNow,
                iconName: "checkmark.seal.fill",
                iconColor: .statusReviewed
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(completedAccessibilityLabel))
        }
    }

    private func summary(
        title: String,
        subtitle: String,
        iconName: String,
        iconColor: Color
    ) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.appHeadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var continueAccessibilityLabel: String {
        String(
            format: CleanupL10n.Main.continueReviewClustersReviewedRemaining,
            progress.reviewedCount,
            progress.totalClusters,
            progress.remainingClusters,
            progress.totalSelectedItems,
            ByteCountFormatter.string(fromByteCount: progress.reviewedSavingsBytes, countStyle: .file)
        )
    }

    private var completedAccessibilityLabel: String {
        String(
            format: CleanupL10n.Main.allClustersReviewedSelectedEstimated,
            progress.reviewedCount,
            progress.totalClusters,
            progress.totalSelectedItems,
            ByteCountFormatter.string(fromByteCount: progress.reviewedSavingsBytes, countStyle: .file)
        )
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.caption.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CleanupCategoriesCard: View {
    let categories: [CleanupCategorySummary]
    let isLocked: (CleanupCategoryKind) -> Bool
    let onTap: (CleanupCategorySummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(CleanupL10n.Main.smartCleanup)
                .font(.appHeadline)

            ForEach(categories) { category in
                Button {
                    onTap(category)
                } label: {
                    HStack {
                        Image(systemName: category.kind.presentation.systemImageName)
                            .foregroundStyle(Color.accent)
                        VStack(alignment: .leading) {
                            Text(category.kind.presentation.title)
                                .font(.appHeadline)
                            Text(categoryDetail(category))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: isLocked(category.kind) ? "lock.fill" : "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(Spacing.small)
                    .background(
                        Color.secondary.opacity(ColorOpacity.statusBackground),
                        in: RoundedRectangle(cornerRadius: CornerRadius.small)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(categoryAccessibilityLabel(category)))
                .accessibilityHint(
                    Text(
                        isLocked(category.kind)
                            ? CleanupL10n.Main.opensTheUpgradeOptions
                            : CleanupL10n.Main.openThisCleanupCategory
                    )
                )
            }
        }
        .padding(Spacing.medium)
        .cleanupGlassSurface()
    }

    private func categoryDetail(_ category: CleanupCategorySummary) -> String {
        String(
            format: CleanupL10n.Main.itemsEstimatedReclaimable,
            category.assetCount,
            ByteCountFormatter.string(fromByteCount: category.estimatedSavingsBytes, countStyle: .file)
        )
    }

    private func categoryAccessibilityLabel(_ category: CleanupCategorySummary) -> String {
        let lockedSuffix = isLocked(category.kind) ? ". \(CleanupL10n.Main.locked)" : ""
        return "\(category.kind.presentation.title). \(categoryDetail(category))\(lockedSuffix)"
    }
}

private struct CleanupClusterSection: View {
    let title: String
    let subtitle: String
    let clusters: [IdentifiedCluster]
    let gridColumns: Int
    let workspace: CleanupWorkspaceModel
    let onOpen: (PhotoCluster) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack {
                Text(title)
                    .font(.appHeadline)
                Text("\(clusters.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .cleanupGlassBadge()
                Spacer()
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Spacing.small),
                    count: max(1, gridColumns)
                ),
                spacing: Spacing.small
            ) {
                ForEach(clusters) { identified in
                    let cluster = identified.cluster
                    CleanupClusterCard(
                        cluster: cluster,
                        previewAsset: cluster.bestShotAsset(
                            preferring: workspace.reviewState(for: cluster.id)?.bestShotLocalIdentifier
                        ),
                        status: workspace.reviewStatus(for: cluster.id),
                        resurfacing: workspace.resurfacingState(for: cluster.id)
                    ) {
                        onOpen(cluster)
                    }
                    .id(identified.id)
                }
            }
            .scrollTargetLayout()
        }
    }
}

private struct CleanupClusterCard: View {
    let cluster: PhotoCluster
    /// The cluster's keeper, so the card previews the photo the review is
    /// keeping instead of whichever asset clustering happened to emit first.
    let previewAsset: PHAsset?
    let status: ClusterReviewStatus
    let resurfacing: ClusterResurfacingState?
    let open: () -> Void

    @Environment(\.colorScheme) private var colorScheme

#if os(iOS)
    @State private var image: UIImage?
    @State private var imageLoadState = PhotoImageLoadState()
    @State private var imageLoadAttempt = 0
#endif

    var body: some View {
        ZStack {
            Button(action: open) {
                ZStack(alignment: .bottomTrailing) {
                    thumbnail
                    Text("\(cluster.count)")
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 28, height: 28)
                        .cleanupGlassBadge(.circle)
                        .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    Label(statusTitle, systemImage: statusIconName)
                        .font(.caption2.bold())
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(5)
                        .cleanupGlassBadge()
                        .padding(5)
                }
                .overlay(alignment: .bottomLeading) {
                    if let resurfacing, resurfacing != .unchanged {
                        Image(systemName: resurfacing == .new ? "sparkles" : "arrow.triangle.2.circlepath")
                            .padding(6)
                            .cleanupGlassBadge(.circle)
                            .padding(5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(clusterAccessibilityLabel))
            .accessibilityHint(Text(CleanupL10n.Main.openThisClusterReviewPhotos))
#if os(iOS)
            if imageLoadState.phase == .failed {
                PhotoLoadFailureView {
                    imageLoadAttempt += 1
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.small))
            }
#endif
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
#if os(iOS)
        PhotoThumbnailAspectRatioLayout(aspectRatio: 1) {
            ZStack {
                placeholder

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .task(id: imageLoadTaskID) {
            await loadThumbnail()
        }
#else
        PhotoThumbnailAspectRatioLayout(aspectRatio: 1) {
            placeholder
        }
        .frame(maxWidth: .infinity)
#endif
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.secondary.opacity(ColorOpacity.placeholderFill))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }

#if os(iOS)
    private var imageLoadTaskID: String {
        "\(previewAsset?.localIdentifier ?? "missing")#\(imageLoadAttempt)"
    }

    @MainActor
    private func loadThumbnail() async {
        guard let asset = previewAsset else { return }

        image = nil
        let generation = imageLoadState.begin()
        do {
            guard let loadedImage = try await asset.loadImage(
                targetSize: CGSize(width: 1_000, height: 1_000)
            ) else {
                imageLoadState.resolve(.failed, generation: generation)
                return
            }
            guard imageLoadState.resolve(.loaded, generation: generation) else { return }
            image = loadedImage
        } catch is CancellationError {
            imageLoadState.resolve(.cancelled, generation: generation)
        } catch {
            imageLoadState.resolve(.failed, generation: generation)
        }
    }
#endif

    private var statusTitle: String {
        switch status {
        case .notReviewed:
            CleanupL10n.Main.notReviewed
        case .needsReReview:
            CleanupL10n.Main.needsReview
        case .inReview:
            CleanupL10n.Main.inReview
        case .reviewed:
            CleanupL10n.Main.reviewed
        }
    }

    private var statusIconName: String {
        switch status {
        case .notReviewed:
            "circle"
        case .needsReReview:
            "arrow.triangle.2.circlepath.circle.fill"
        case .inReview:
            "clock.arrow.circlepath"
        case .reviewed:
            "checkmark.seal.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .notReviewed:
            colorScheme == .dark ? .primary.opacity(0.85) : .secondary
        case .needsReReview:
            .statusNeedsReview
        case .inReview:
            .statusInReview
        case .reviewed:
            .statusReviewed
        }
    }

    private var clusterAccessibilityLabel: String {
        let resurfacingTitle: String
        switch resurfacing {
        case .new:
            resurfacingTitle = CleanupL10n.Main.new
        case .changed:
            resurfacingTitle = CleanupL10n.Main.changed
        case .none, .unchanged:
            resurfacingTitle = ""
        }

        return [
            String(format: CleanupL10n.Common.photos, cluster.count),
            statusTitle,
            resurfacingTitle
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ". ")
    }
}

private struct CleanupStatusBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var showsProgress = false
    var progress: Double? = nil
    var dismiss: (() -> Void)? = nil

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLayout
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalLayout
                    stackedLayout
                }
            }
        }
        .padding(Spacing.medium)
        .cleanupGlassSurface()
    }

    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            indicator
            statusText(allowsWrapping: false)
            Spacer(minLength: Spacing.small)
            compactAction
            dismissButton
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .top, spacing: Spacing.small) {
                indicator
                statusText(allowsWrapping: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                dismissButton
            }

            expandedAction
        }
    }

    @ViewBuilder
    private var indicator: some View {
        if showsProgress {
            ProgressView(value: progress)
                .frame(width: 22)
        } else {
            Image(systemName: icon)
                .foregroundStyle(Color.accent)
        }
    }

    private func statusText(allowsWrapping: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.appHeadline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: !allowsWrapping, vertical: true)
    }

    @ViewBuilder
    private var compactAction: some View {
        if let actionTitle, let action {
            Button(actionTitle, action: action)
                .fixedSize(horizontal: true, vertical: false)
                .cleanupGlassButton()
        }
    }

    @ViewBuilder
    private var expandedAction: some View {
        if let actionTitle, let action {
            Button(action: action) {
                Text(actionTitle)
                    .frame(maxWidth: .infinity)
            }
            .cleanupGlassButton()
        }
    }

    @ViewBuilder
    private var dismissButton: some View {
        if let dismiss {
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .cleanupGlassButton()
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text(CleanupL10n.Main.dismissCleanupStatus))
            .accessibilityHint(Text(CleanupL10n.Main.hideThisStatusMessage))
        }
    }
}

#Preview("Library Changed") {
    CleanupStatusBanner(
        icon: "photo.badge.arrow.down",
        title: CleanupL10n.Main.yourLibraryChanged,
        message: CleanupL10n.Main.runNewScanRefreshCleanup,
        actionTitle: CleanupL10n.Main.rescan,
        action: {}
    )
    .padding()
}

#Preview("Refresh Failure") {
    CleanupStatusBanner(
        icon: "exclamationmark.triangle.fill",
        title: CleanupL10n.Main.refreshRequired,
        message: CleanupL10n.Main.photosWereDeletedButLibrary,
        actionTitle: CleanupL10n.Main.rescan,
        action: {},
        dismiss: {}
    )
    .padding()
}
