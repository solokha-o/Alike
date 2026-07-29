import SwiftUI
import Photos
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
    }

    private let workspace: CleanupWorkspaceModel
    @Binding private var sensitivity: SensitivityLevel
    private let premiumAccess: any PremiumAccessControlling
    private let subscriptionStore: SubscriptionStore?
    private let onOpenScanner: @MainActor @Sendable () -> Void
    private let onRequestScan: @MainActor @Sendable () -> Void

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var compactGridColumns = AdaptivePhotoGridLayoutPolicy.compact.defaultColumnCount
    @State private var regularGridColumns = AdaptivePhotoGridLayoutPolicy.regular.defaultColumnCount
    @State private var controls = CleanupClusterControls()
    @State private var isControlsPresented = false
    @State private var presentedCategory: PresentedCleanupCategory?
    @State private var presentedPaywall: PremiumFeature?
    @State private var categoryError: String?
    @State private var dismissedReconciliationID: UUID?

    public init(
        workspace: CleanupWorkspaceModel,
        sensitivity: Binding<SensitivityLevel>,
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        subscriptionStore: SubscriptionStore? = nil,
        onOpenScanner: @escaping @MainActor @Sendable () -> Void,
        onRequestScan: @escaping @MainActor @Sendable () -> Void
    ) {
        self.workspace = workspace
        self._sensitivity = sensitivity
        self.premiumAccess = premiumAccess
        self.subscriptionStore = subscriptionStore
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
        .alert(appLocalized("Couldn't Open Cleanup Category"), isPresented: errorBinding) {
            Button(appLocalized("OK"), role: .cancel) { categoryError = nil }
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
        .overlay(alignment: .top) {
            reconciliationOverlay
                .animation(
                    accessibilityReduceMotion ? nil : .appSmooth,
                    value: workspace.reconciliationState
                )
        }
        .navigationTitle(Text(appLocalized("Cleanup")))
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .toolbar { cleanupToolbar }
        .animation(.appSmooth, value: displayedScanOperation)
    }

    private func cleanupStack(router: StackRouter<CleanupRoute>) -> some View {
        VStack(spacing: Spacing.medium) {
            persistentBanners
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
                title: appLocalized("Refreshing Cleanup"),
                message: String(format: appLocalized("Scanning your library… %d%%"), Int(progress * 100)),
                showsProgress: true,
                progress: progress
            )
        } else if case .failed(let message, .userInitiated) = workspace.scanOperation {
            CleanupStatusBanner(
                icon: "exclamationmark.triangle.fill",
                title: appLocalized("Scan Failed"),
                message: message
            )
        }
        if workspace.shouldShowRescanPrompt {
            CleanupStatusBanner(
                icon: "photo.badge.arrow.down",
                title: appLocalized("Your library changed"),
                message: appLocalized("Run a new scan to refresh cleanup suggestions."),
                actionTitle: appLocalized("Rescan"),
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
                title: String(format: appLocalized("%d photos moved to Recently Deleted."), record.deletedCount),
                message: appLocalized("Your cleanup results are up to date."),
                dismiss: { dismissReconciliation(record.id) }
            )
        case .failed(let record, let message):
            CleanupStatusBanner(
                icon: "exclamationmark.triangle.fill",
                title: appLocalized("Refresh Required"),
                message: message,
                actionTitle: appLocalized("Rescan"),
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
            Label(appLocalized("Scan Your Library First"), systemImage: "viewfinder")
        } description: {
            Text(appLocalized("Start a scan to find similar photos and smart cleanup suggestions."))
        } actions: {
            Button(appLocalized("Go to Scanner"), action: onOpenScanner)
                .cleanupGlassButton(isProminent: true)
        }
        .frame(minHeight: 360)
    }

    private func unavailable(_ message: String) -> some View {
        ContentUnavailableView {
            Label(appLocalized("Cleanup Unavailable"), systemImage: "exclamationmark.triangle")
        } description: { Text(message) } actions: {
            Button(appLocalized("Go to Scanner"), action: onOpenScanner)
                .cleanupGlassButton()
        }
        .frame(minHeight: 360)
    }

    @ViewBuilder
    private func cleanupContent(router: StackRouter<CleanupRoute>) -> some View {
        let allClusters = sorted(workspace.clusters)
        let visible = filtered(allClusters)
        let needsReview = visible.filter { workspace.reviewStatus(for: $0.id) == .needsReReview }
        let remaining = visible.filter { workspace.reviewStatus(for: $0.id) != .needsReReview }

        if let entry = workspace.cleanupEntryCluster() {
            CleanupProgressCard(
                progress: workspace.sessionProgress(),
                onContinue: { router.push(.cluster(entry)) },
                onOpenHistory: { router.push(.history) }
            )
        }
        if !workspace.cleanupCategories.isEmpty {
            CleanupCategoriesCard(categories: workspace.cleanupCategories, isLocked: { !premiumAccess.hasAccess(to: $0.premiumFeature) }, onTap: openCategory)
        }
        if allClusters.isEmpty && workspace.cleanupCategories.isEmpty {
            ContentUnavailableView {
                Label(appLocalized("No Cleanup Opportunities"), systemImage: "checkmark.seal")
            } description: { Text(appLocalized("Your latest scan did not find similar photos or smart categories to review.")) }
            .padding(.top, Spacing.xxLarge)
        } else if visible.isEmpty && !allClusters.isEmpty {
            ContentUnavailableView {
                Label(appLocalized("No Clusters Match These Controls"), systemImage: "line.3.horizontal.decrease.circle")
            } description: { Text(appLocalized("Try changing filters or resetting controls.")) } actions: {
                Button(appLocalized("Reset controls")) { controls = CleanupClusterControls() }
                    .cleanupGlassButton()
            }
        } else {
            if !needsReview.isEmpty {
                CleanupClusterSection(title: appLocalized("Needs review"), subtitle: appLocalized("New and changed clusters after your latest rescan"), clusters: needsReview, gridColumns: selectedGridColumnCount, workspace: workspace) { router.push(.cluster($0)) }
            }
            if !remaining.isEmpty {
                CleanupClusterSection(title: appLocalized("All clusters"), subtitle: appLocalized("Everything else still available in your cleanup queue"), clusters: remaining, gridColumns: selectedGridColumnCount, workspace: workspace) { router.push(.cluster($0)) }
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
        Menu {
            Picker(selection: selectedGridColumnBinding) {
                ForEach(gridLayoutPolicy.columnCounts, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            } label: {
                Text(appLocalized("Columns"))
            }
        } label: {
            Image(systemName: "square.grid.3x2")
        }
        .accessibilityLabel(Text(appLocalized("Grid Columns")))
        .accessibilityHint(Text(appLocalized("Choose how many columns are used to display photos")))
    }

    private var gridLayoutPolicy: AdaptivePhotoGridLayoutPolicy {
#if os(iOS)
        horizontalSizeClass == .regular ? .regular : .compact
#else
        .regular
#endif
    }

    private var selectedGridColumnCount: Int {
#if os(iOS)
        horizontalSizeClass == .regular ? regularGridColumns : compactGridColumns
#else
        regularGridColumns
#endif
    }

    private var selectedGridColumnBinding: Binding<Int> {
        Binding(
            get: { selectedGridColumnCount },
            set: { newValue in
                guard gridLayoutPolicy.columnCounts.contains(newValue) else { return }
#if os(iOS)
                if horizontalSizeClass == .regular {
                    regularGridColumns = newValue
                } else {
                    compactGridColumns = newValue
                }
#else
                regularGridColumns = newValue
#endif
            }
        )
    }

    private var controlsButton: some View {
        Button { isControlsPresented = true } label: {
            Image(systemName: controls.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel(Text(appLocalized("Filter and sort clusters")))
    }

    private var rescanButton: some View {
        Button(action: onRequestScan) { Image(systemName: "arrow.clockwise") }
            .accessibilityLabel(Text(appLocalized("Rescan Photos")))
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

    private func filtered(_ clusters: [PhotoCluster]) -> [PhotoCluster] {
        clusters.filter { cluster in
            guard premiumAccess.hasAccess(to: .advancedFilters) else { return true }
            let status = workspace.reviewStatus(for: cluster.id)
            let reviewMatches: Bool
            switch controls.reviewFilter {
            case .all: reviewMatches = true
            case .needsReview: reviewMatches = status == .needsReReview
            case .inReview: reviewMatches = status == .inReview
            case .reviewed: reviewMatches = status == .reviewed
            }
            return reviewMatches
                && cluster.count >= controls.minimumClusterSize.rawValue
                && (!controls.favoritesOnly || cluster.assets.contains(where: \.isFavorite))
        }
    }

    private func sorted(_ clusters: [PhotoCluster]) -> [PhotoCluster] {
        clusters.sorted { lhs, rhs in
            switch controls.sort {
            case .newest: lhs.createdAt > rhs.createdAt
            case .largestCluster: lhs.count > rhs.count
            case .similarity: lhs.averageSimilarity > rhs.averageSimilarity
            case .reviewStatus: workspace.reviewStatus(for: lhs.id).rawValue < workspace.reviewStatus(for: rhs.id).rawValue
            case .largestCleanupOpportunity:
                (workspace.reviewState(for: lhs.id)?.estimatedSavingsBytes ?? 0)
                    > (workspace.reviewState(for: rhs.id)?.estimatedSavingsBytes ?? 0)
            }
        }
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
            appLocalized("Newest")
        case .largestCleanupOpportunity:
            appLocalized("Most space to save")
        case .largestCluster:
            appLocalized("Largest cluster")
        case .similarity:
            appLocalized("Highest similarity")
        case .reviewStatus:
            appLocalized("Review status")
        }
    }
}

public enum CleanupReviewFilter: String, CaseIterable, Sendable {
    case all
    case needsReview
    case inReview
    case reviewed

    var title: String {
        switch self {
        case .all:
            appLocalized("All review states")
        case .needsReview:
            appLocalized("Needs review")
        case .inReview:
            appLocalized("In review")
        case .reviewed:
            appLocalized("Reviewed")
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
            ? appLocalized("Any size")
            : String(format: appLocalized("%d or more photos"), rawValue)
    }
}
public struct CleanupClusterControls: Equatable, Sendable {
    public var sort: CleanupClusterSort = .newest
    public var reviewFilter: CleanupReviewFilter = .all
    public var minimumClusterSize: CleanupMinimumClusterSize = .any
    public var favoritesOnly = false
    public var isDefault: Bool { self == Self() }

    public init() {}
}

private struct CleanupClusterControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var controls: CleanupClusterControls
    let isAdvancedFilteringLocked: Bool
    let onRequestAdvancedFilters: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(appLocalized("Sort by")) {
                    Picker(appLocalized("Sort order"), selection: $controls.sort) {
                        ForEach(CleanupClusterSort.allCases, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                }

                Section(appLocalized("Filter by")) {
                    if isAdvancedFilteringLocked {
                        Button(action: onRequestAdvancedFilters) {
                            Label(appLocalized("Unlock advanced filters"), systemImage: "lock.fill")
                        }
                    } else {
                        Picker(appLocalized("Review status"), selection: $controls.reviewFilter) {
                            ForEach(CleanupReviewFilter.allCases, id: \.self) {
                                Text($0.title).tag($0)
                            }
                        }
                        Picker(appLocalized("Minimum cluster size"), selection: $controls.minimumClusterSize) {
                            ForEach(CleanupMinimumClusterSize.allCases, id: \.self) {
                                Text($0.title).tag($0)
                            }
                        }
                        Toggle(appLocalized("Favorites only"), isOn: $controls.favoritesOnly)
                    }
                }

                Section {
                    Button(appLocalized("Reset controls"), role: .destructive) {
                        controls = CleanupClusterControls()
                    }
                    .disabled(controls.isDefault)
                }
            }
            .navigationTitle(Text(appLocalized("Filter and Sort")))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(appLocalized("Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CleanupProgressCard: View {
    let progress: CleanupSessionProgress
    let onContinue: () -> Void
    let onOpenHistory: () -> Void
    private let metricColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .top, spacing: Spacing.small) {
                Button(action: onContinue) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(appLocalized("Continue Review")).font(.appHeadline)
                            Text(appLocalized("Pick up where you left off"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(continueAccessibilityLabel))
                .accessibilityHint(Text(appLocalized("Open next cluster to continue cleanup")))

                Button(action: onOpenHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .frame(width: 22, height: 22)
                }
                .cleanupGlassButton()
                .controlSize(.small)
                .accessibilityLabel(Text(appLocalized("Cleanup History")))
            }

            ProgressView(value: progress.reviewedRatio)
            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: Spacing.small) {
                metric("\(progress.reviewedCount)/\(progress.totalClusters)", appLocalized("Reviewed"))
                metric("\(progress.remainingClusters)", appLocalized("Remaining"))
                metric("\(progress.totalSelectedItems)", appLocalized("Selected"))
                metric(ByteCountFormatter.string(fromByteCount: progress.reviewedSavingsBytes, countStyle: .file), appLocalized("Estimated Savings"))
            }
        }
        .padding(Spacing.medium)
        .cleanupGlassSurface()
    }

    private var continueAccessibilityLabel: String {
        String(
            format: appLocalized("Continue review. %d of %d clusters reviewed, %d remaining, %d selected, %@ estimated savings."),
            progress.reviewedCount,
            progress.totalClusters,
            progress.remainingClusters,
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
            Text(appLocalized("Smart Cleanup"))
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
                            ? appLocalized("Opens the upgrade options")
                            : appLocalized("Open this cleanup category")
                    )
                )
            }
        }
        .padding(Spacing.medium)
        .cleanupGlassSurface()
    }

    private func categoryDetail(_ category: CleanupCategorySummary) -> String {
        String(
            format: appLocalized("%d items • %@ estimated reclaimable"),
            category.assetCount,
            ByteCountFormatter.string(fromByteCount: category.estimatedSavingsBytes, countStyle: .file)
        )
    }

    private func categoryAccessibilityLabel(_ category: CleanupCategorySummary) -> String {
        let lockedSuffix = isLocked(category.kind) ? ". \(appLocalized("Locked"))" : ""
        return "\(category.kind.presentation.title). \(categoryDetail(category))\(lockedSuffix)"
    }
}

private struct CleanupClusterSection: View {
    let title: String
    let subtitle: String
    let clusters: [PhotoCluster]
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
                ForEach(clusters) { cluster in
                    CleanupClusterCard(
                        cluster: cluster,
                        status: workspace.reviewStatus(for: cluster.id),
                        resurfacing: workspace.resurfacingState(for: cluster.id)
                    ) {
                        onOpen(cluster)
                    }
                }
            }
        }
    }
}

private struct CleanupClusterCard: View {
    let cluster: PhotoCluster
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
            .accessibilityHint(Text(appLocalized("Open this cluster to review photos")))
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
        "\(cluster.thumbnail?.localIdentifier ?? "missing")#\(imageLoadAttempt)"
    }

    @MainActor
    private func loadThumbnail() async {
        guard let asset = cluster.thumbnail else { return }

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
            appLocalized("Not reviewed")
        case .needsReReview:
            appLocalized("Needs review")
        case .inReview:
            appLocalized("In review")
        case .reviewed:
            appLocalized("Reviewed")
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
            resurfacingTitle = appLocalized("New")
        case .changed:
            resurfacingTitle = appLocalized("Changed")
        case .none, .unchanged:
            resurfacingTitle = ""
        }

        return [
            String(format: appLocalized("%d photos"), cluster.count),
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
            .accessibilityLabel(Text(appLocalized("Dismiss cleanup status")))
            .accessibilityHint(Text(appLocalized("Hide this status message")))
        }
    }
}

#Preview("Library Changed") {
    CleanupStatusBanner(
        icon: "photo.badge.arrow.down",
        title: appLocalized("Your library changed"),
        message: appLocalized("Run a new scan to refresh cleanup suggestions."),
        actionTitle: appLocalized("Rescan"),
        action: {}
    )
    .padding()
}

#Preview("Refresh Failure") {
    CleanupStatusBanner(
        icon: "exclamationmark.triangle.fill",
        title: appLocalized("Refresh Required"),
        message: appLocalized("The photos were deleted, but the library refresh failed. Run a new scan to refresh your results."),
        actionTitle: appLocalized("Rescan"),
        action: {},
        dismiss: {}
    )
    .padding()
}
