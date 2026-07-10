import SwiftUI
import Core
import DesignSystem
import Details
import Photos
import Cleanup
import NavigationKit

private enum ScannerRoute: Hashable {
    case clusterDetails(PhotoCluster)
}

private struct PresentedCleanupCategory: Identifiable {
    let kind: CleanupCategoryKind
    let assets: [PHAsset]

    var id: CleanupCategoryKind { kind }
}

/// Scanner screen with analysis and results
public struct ScannerView: View {
    @State private var viewModel: ScannerViewModel
    @State private var presentedCleanupCategory: PresentedCleanupCategory?
    @State private var presentedPaywallFeature: PremiumFeature?
    @State private var cleanupCategoryErrorMessage: String?
    @State private var isClusterControlsPresented = false
    @Binding var gridColumns: Int
    @Binding var sensitivity: SensitivityLevel
    @Binding var shouldStartScan: Bool
    
    public init(
        gridColumns: Binding<Int>,
        sensitivity: Binding<SensitivityLevel>,
        shouldStartScan: Binding<Bool> = .constant(false),
        viewModel: ScannerViewModel? = nil
    ) {
        self._gridColumns = gridColumns
        self._sensitivity = sensitivity
        self._shouldStartScan = shouldStartScan
        if let viewModel {
            self._viewModel = State(initialValue: viewModel)
        } else {
            self._viewModel = State(initialValue: ScannerViewModel(
                gridColumns: gridColumns.wrappedValue,
                sensitivity: sensitivity.wrappedValue
            ))
        }
    }
    
    public var body: some View {
        RoutedNavigationStack { router in
            content(router: router)
        } destination: { route, _ in
            destination(for: route)
        }
        .task {
            await viewModel.loadCachedResults()
            _ = await viewModel.checkForGalleryChanges()
        }
        .onChange(of: gridColumns) { _, newValue in
            viewModel.gridColumns = newValue
        }
        .onChange(of: sensitivity) { _, newValue in
            viewModel.sensitivity = newValue
        }
        .onChange(of: shouldStartScan) { _, newValue in
            if newValue {
                Task {
                    await viewModel.startScanning()
                    shouldStartScan = false
                }
            }
        }
        .sheet(item: $presentedCleanupCategory) { presented in
            RoutedNavigationStack {
                ScreenshotCleanupView(
                    assets: presented.assets,
                    sourceCategory: presented.kind,
                    cleanupService: viewModel.cleanupService,
                    cleanupHistoryRepository: viewModel.cleanupHistoryRepository,
                    openSettingsAction: {
                        PhotoPermissionManagerImpl().openSettings()
                    },
                    onCleanupCompleted: { record in
                        Task {
                            await viewModel.handleCleanupCompleted(record)
                        }
                    }
                )
            }
            .interactiveDismissDisabled()
        }
        .sheet(item: $presentedPaywallFeature) { feature in
            PremiumPaywallSheet(feature: feature)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $isClusterControlsPresented) {
            ScannerClusterControlsSheet(controls: $viewModel.clusterControls)
        }
        .alert(
            appLocalized("Couldn't Open Cleanup Category"),
            isPresented: Binding(
                get: { cleanupCategoryErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        cleanupCategoryErrorMessage = nil
                    }
                }
            )
        ) {
            Button(appLocalized("OK"), role: .cancel) {
                cleanupCategoryErrorMessage = nil
            }
        } message: {
            Text(cleanupCategoryErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private func content(router: StackRouter<ScannerRoute>) -> some View {
        VStack(spacing: Spacing.medium) {
            if let cleanupRefreshState = viewModel.cleanupRefreshState {
                CleanupRefreshBanner(
                    state: cleanupRefreshState,
                    onRetry: {
                        Task {
                            await viewModel.retryCleanupRefresh()
                        }
                    },
                    onDismiss: viewModel.dismissCleanupRefreshState
                )
                .padding(.horizontal, Spacing.medium)
                .padding(.top, Spacing.small)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
                .zIndex(1)
            }

            Group {
                switch viewModel.state {
                case .idle:
                    idleView
                case .scanning(let progress):
                    scanningView(progress: progress)
                case .results(let clusters):
                    resultsView(clusters: clusters, router: router)
                case .error(let message):
                    errorView(message: message)
                }
            }
        }
        .navigationTitle(Text(appLocalized("Scanner")))
        .animation(.appSmooth, value: viewModel.cleanupRefreshState != nil)
        .animation(.appSmooth, value: viewModel.cleanupRefreshState)
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        }
    
    @ViewBuilder
    private func destination(for route: ScannerRoute) -> some View {
        switch route {
        case .clusterDetails(let cluster):
            ClusterDetailsView(
                cluster: cluster,
                cleanupService: viewModel.cleanupService,
                cleanupHistoryRepository: viewModel.cleanupHistoryRepository,
                openSettingsAction: {
                    PhotoPermissionManagerImpl().openSettings()
                },
                onReviewStateChanged: {
                    Task {
                        await viewModel.loadReviewStates()
                    }
                },
                onCleanupCompleted: { record in
                    Task {
                        await viewModel.handleCleanupCompleted(record)
                    }
                }
            )
        }
    }
    
    // MARK: - Idle View
    private var idleView: some View {
        VStack(spacing: Spacing.xLarge) {
            Spacer()
            
            Image(systemName: "photo.stack")
                .font(.system(size: 80))
                .foregroundColor(.accent)
            
            Text(appLocalized("Ready to Scan"))
                .font(.appTitle)
                .foregroundColor(.primary)
            
            Text(appLocalized("Tap the button below to analyze your photo library"))
                .font(.appBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xLarge)

            if viewModel.cleanupInsights.hasHistory {
                CleanupInsightsCard(insights: viewModel.cleanupInsights)
                    .padding(.horizontal, Spacing.medium)
            }
            
            Spacer()
            
            PrimaryButton(appLocalized("Start Scanning"), icon: "sparkles") {
                Task {
                    await viewModel.startScanning()
                }
            }
            .padding(.horizontal, Spacing.large)
            .padding(.bottom, Spacing.xLarge)
        }
    }
    
    // MARK: - Scanning View
    private func scanningView(progress: Double) -> some View {
        VStack(spacing: Spacing.xxLarge) {
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(Color.accent.opacity(ColorOpacity.progressTrack), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.appSmooth, value: progress)
                
                Text("\(Int(progress * 100))%")
                    .font(.title.bold())
                    .foregroundColor(.accent)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(appLocalized("Scanning progress")))
            .accessibilityValue(Text("\(Int(progress * 100))%"))
            
            Text(appLocalized("Analyzing Photos..."))
                .font(.appTitle2)
                .foregroundColor(.primary)
            
            Text(appLocalized("Finding visually similar images"))
                .font(.appBody)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Results View
    private func resultsView(
        clusters: [PhotoCluster],
        router: StackRouter<ScannerRoute>
    ) -> some View {
        let sortedClusters = viewModel.sortedClusters(from: clusters)
        let needsReviewClusters = viewModel.needsReviewClusters(from: sortedClusters)
        let remainingClusters = viewModel.remainingClusters(from: sortedClusters)
        let sessionProgress = viewModel.displayedSessionProgress(for: sortedClusters)

        return ScrollView {
            VStack(spacing: Spacing.medium) {
                if viewModel.cleanupInsights.hasHistory {
                    CleanupInsightsCard(insights: viewModel.cleanupInsights)
                }

                if !viewModel.cleanupCategories.isEmpty {
                    CleanupCategoriesCard(
                        categories: viewModel.cleanupCategories,
                        isLocked: viewModel.isCategoryLocked(_:),
                        onTapCategory: { category in
                            Task {
                                await openCleanupCategory(category)
                            }
                        }
                    )
                }

                if sortedClusters.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text(viewModel.clusterControls.isDefault
                                 ? appLocalized("No Similar Photos Found")
                                 : appLocalized("No Clusters Match These Controls"))
                        } icon: {
                            Image(systemName: "photo.stack")
                        }
                    } description: {
                        Text(viewModel.clusterControls.isDefault
                             ? appLocalized("Try adjusting sensitivity in Settings")
                             : appLocalized("Try changing the filters or reset the controls"))
                    }
                    .padding(.top, viewModel.cleanupCategories.isEmpty ? 100 : Spacing.large)
                } else {
                    if viewModel.shouldShowRescanPrompt {
                        RescanPromptCard {
                            Task {
                                await viewModel.startScanning()
                            }
                        }
                    }

                    if !needsReviewClusters.isEmpty {
                        ClusterSectionCard(
                            title: appLocalized("Needs review"),
                            subtitle: appLocalized("New and changed clusters after your latest rescan"),
                            badgeText: "\(needsReviewClusters.count)",
                            clusters: needsReviewClusters,
                            gridColumns: gridColumns,
                            reviewStatus: viewModel.reviewStatus(for:),
                            resurfacingState: viewModel.resurfacingState(for:),
                            onOpenCluster: { cluster in
                                router.push(.clusterDetails(cluster))
                            }
                        )
                    }

                    CleanupSessionProgressCard(
                        progress: sessionProgress,
                        onTap: {
                            guard let cluster = viewModel.cleanupEntryCluster(from: sortedClusters) else {
                                return
                            }
                            router.push(.clusterDetails(cluster))
                        }
                    )

                    if !remainingClusters.isEmpty {
                        ClusterSectionCard(
                            title: appLocalized("All clusters"),
                            subtitle: appLocalized("Everything else that is still available in your cleanup queue"),
                            badgeText: "\(remainingClusters.count)",
                            clusters: remainingClusters,
                            gridColumns: gridColumns,
                            reviewStatus: viewModel.reviewStatus(for:),
                            resurfacingState: viewModel.resurfacingState(for:),
                            onOpenCluster: { cluster in
                                router.push(.clusterDetails(cluster))
                            }
                        )
                    }
                }
            }
            .padding(Spacing.medium)
        }
        .onAppear {
            Task {
                await viewModel.loadReviewStates()
            }
        }
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isClusterControlsPresented = true
                } label: {
                    Image(systemName: viewModel.clusterControls.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel(Text(appLocalized("Filter and sort clusters")))
                .accessibilityValue(Text(activeControlsSummary))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.startScanning()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .scaleOnPress()
                .accessibilityLabel(Text(appLocalized("Rescan Photos")))
                .accessibilityHint(Text(appLocalized("Starts scanning your photo library again")))
            }
#else
            ToolbarItem {
                Button {
                    isClusterControlsPresented = true
                } label: {
                    Image(systemName: viewModel.clusterControls.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel(Text(appLocalized("Filter and sort clusters")))
                .accessibilityValue(Text(activeControlsSummary))
            }
            ToolbarItem {
                Button {
                    Task {
                        await viewModel.startScanning()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .scaleOnPress()
                .accessibilityLabel(Text(appLocalized("Rescan Photos")))
                .accessibilityHint(Text(appLocalized("Starts scanning your photo library again")))
            }
#endif
        }
        .sensoryFeedback(.success, trigger: clusters.count)
    }

    private var activeControlsSummary: String {
        guard !viewModel.clusterControls.isDefault else { return appLocalized("No active controls") }
        var values = [viewModel.clusterControls.sort.title]
        if viewModel.clusterControls.reviewFilter != .all {
            values.append(viewModel.clusterControls.reviewFilter.title)
        }
        if viewModel.clusterControls.minimumClusterSize != .any {
            values.append(viewModel.clusterControls.minimumClusterSize.title)
        }
        if viewModel.clusterControls.favoritesOnly {
            values.append(appLocalized("Favorites only"))
        }
        return values.joined(separator: ", ")
    }

    private func openCleanupCategory(_ category: CleanupCategorySummary) async {
        if viewModel.isCategoryLocked(category.kind) {
            presentedPaywallFeature = category.kind.premiumFeature
            return
        }

        do {
            let assets = try await viewModel.loadAssets(for: category.kind)
            presentedCleanupCategory = PresentedCleanupCategory(kind: category.kind, assets: assets)
        } catch {
            cleanupCategoryErrorMessage = error.localizedDescription
        }
    }

    
    // MARK: - Error View
    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label {
                Text(appLocalized("Scan Failed"))
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } description: {
            Text(message)
        }
    }
}

private struct CleanupInsightsCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let insights: CleanupInsights

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(appLocalized("Cleanup History"))
                .font(.appHeadline)

            HStack(spacing: Spacing.small) {
                metricItem(
                    title: appLocalized("Saved So Far"),
                    value: ByteCountFormatter.string(fromByteCount: insights.totalSavedBytes, countStyle: .file),
                    color: .statusSavings
                )
                metricItem(
                    title: appLocalized("Photos Deleted"),
                    value: "\(insights.totalDeletedItems)",
                    color: .accent
                )
            }

            if let latestCleanup = insights.latestCleanup {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(appLocalized("Latest cleanup"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(latestCleanupSummary(for: latestCleanup))
                        .font(.appSubheadline)
                    Text(relativeDateText(for: latestCleanup.completedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, Spacing.xxSmall)
            }
        }
        .padding(Spacing.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(appLocalized("Cleanup History")))
        .accessibilityValue(Text(accessibilitySummary))
    }

    private func metricItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: Spacing.xxSmall) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xSmall)
        .background(color.opacity(metricBackgroundOpacity), in: RoundedRectangle(cornerRadius: CornerRadius.small))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }

    private func latestCleanupSummary(for record: CleanupCompletionRecord) -> String {
        let savingsText = ByteCountFormatter.string(fromByteCount: record.estimatedSavingsBytes, countStyle: .file)
        return "\(record.deletedCount) \(appLocalized("photos deleted")) • \(savingsText) \(appLocalized("saved"))"
    }

    private func relativeDateText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var accessibilitySummary: String {
        let savedText = ByteCountFormatter.string(fromByteCount: insights.totalSavedBytes, countStyle: .file)
        return "\(savedText) \(appLocalized("saved so far")), \(insights.totalDeletedItems) \(appLocalized("photos deleted"))"
    }

    private var metricBackgroundOpacity: Double {
        colorScheme == .dark ? ColorOpacity.statusBackgroundDark : ColorOpacity.statusBackground
    }
}

private struct ScannerClusterControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var controls: ScannerClusterControls

    var body: some View {
        NavigationStack {
            Form {
                Section(appLocalized("Sort by")) {
                    Picker(appLocalized("Sort order"), selection: $controls.sort) {
                        ForEach(ScannerClusterSort.allCases, id: \.self) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                }

                Section(appLocalized("Filter by")) {
                    Picker(appLocalized("Review status"), selection: $controls.reviewFilter) {
                        ForEach(ScannerReviewFilter.allCases, id: \.self) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    Picker(appLocalized("Minimum cluster size"), selection: $controls.minimumClusterSize) {
                        ForEach(ScannerMinimumClusterSize.allCases, id: \.self) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    Toggle(appLocalized("Favorites only"), isOn: $controls.favoritesOnly)
                }

                Section {
                    Button(appLocalized("Reset controls"), role: .destructive) {
                        controls = ScannerClusterControls()
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

private struct CleanupRefreshBanner: View {
    let state: ScannerViewModel.CleanupRefreshState
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            icon

            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(title)
                    .font(.appHeadline)
                Text(message)
                    .font(.appBody)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.small)

            actionArea
        }
        .padding(Spacing.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
        .subtleShadow()
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .refreshing:
            ProgressView()
                .tint(.accent)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.statusReviewed)
                .font(.title3)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusNeedsReview)
                .font(.title3)
        }
    }

    private var title: String {
        switch state {
        case .refreshing(let record):
            "Deleted \(record.deletedCount) photos."
        case .success(let record):
            "Deleted \(record.deletedCount) photos."
        case .failed:
            appLocalized("Refresh Required")
        }
    }

    private var message: String {
        switch state {
        case .refreshing:
            appLocalized("Refreshing results from your photo library...")
        case .success:
            appLocalized("Your cleanup results are up to date.")
        case .failed(_, let message):
            message
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch state {
        case .refreshing:
            EmptyView()
        case .success:
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.headline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text(appLocalized("Dismiss")))
        case .failed:
            HStack(spacing: Spacing.small) {
                Button(appLocalized("Retry")) {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.headline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(appLocalized("Dismiss")))
            }
        }
    }
}

// MARK: - Cluster Card
struct ClusterCard: View {
    let cluster: PhotoCluster
    let gridColumns: Int
    let reviewStatus: ClusterReviewStatus
    let resurfacingState: ClusterResurfacingState?
    let onOpen: () -> Void
#if os(iOS)
    @State private var thumbnailImage: UIImage?
#endif
    
    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .bottomTrailing) {
#if os(iOS)
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: cardHeight)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(ColorOpacity.placeholderFill))
                        .frame(height: cardHeight)
                        .overlay {
                            ProgressView()
                        }
                }
#else
                Rectangle()
                    .fill(Color.secondary.opacity(ColorOpacity.placeholderFill))
                    .frame(height: cardHeight)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
#endif
                
                // Count badge
                Text("\(cluster.count)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.small)
                    .padding(.vertical, Spacing.xxSmall)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(Spacing.xSmall)
            }
            .overlay(alignment: .topLeading) {
                ClusterReviewBadge(status: reviewStatus)
                    .padding(Spacing.xSmall)
            }
            .overlay(alignment: .topTrailing) {
                if let resurfacingState {
                    ClusterResurfacingBadge(state: resurfacingState)
                        .padding(Spacing.xSmall)
                }
            }
            .cornerRadius(CornerRadius.medium)
            .subtleShadow()
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(cluster.count) \(appLocalized("photos"))"))
        .accessibilityValue(Text(reviewStatusTitle))
        .accessibilityHint(Text(appLocalized("Open cluster details to review and select photos")))
#if os(iOS)
        .task {
            if let asset = cluster.thumbnail {
                thumbnailImage = try? await asset.loadImage()
            }
        }
#endif
    }

    private var cardHeight: CGFloat {
        gridColumns == 1 ? 260 : 150
    }

    private var reviewStatusTitle: String {
        switch reviewStatus {
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
}

private struct CleanupSessionProgressCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let progress: CleanupSessionProgress
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack {
                    Text(appLocalized("Cleanup Session Progress"))
                        .font(.appHeadline)
                    Spacer()
                    Label(appLocalized("Continue Cleanup"), systemImage: "arrow.right.circle.fill")
                        .font(.caption.bold())
                }

                HStack(spacing: Spacing.small) {
                    metricItem(title: appLocalized("Total Clusters"), value: "\(progress.totalClusters)", color: .secondary)
                    metricItem(title: appLocalized("Needs review"), value: "\(progress.needsReReviewCount)", color: .statusNeedsReview)
                    metricItem(title: appLocalized("Reviewed"), value: "\(progress.reviewedCount)", color: .statusReviewed)
                }

                HStack(spacing: Spacing.small) {
                    metricItem(title: appLocalized("Left to Review"), value: "\(progress.remainingClusters)", color: .accent)
                    metricItem(title: appLocalized("In review"), value: "\(progress.inReviewCount)", color: .statusInReview)
                    metricItem(title: appLocalized("Not reviewed"), value: "\(progress.notReviewedCount)", color: .secondary)
                }

                HStack(spacing: Spacing.small) {
                    metricItem(title: appLocalized("Total Selected Items"), value: "\(progress.totalSelectedItems)", color: .accent)
                    metricItem(
                        title: appLocalized("Estimated Savings"),
                        value: ByteCountFormatter.string(fromByteCount: progress.reviewedSavingsBytes, countStyle: .file),
                        color: .statusSavings
                    )
                }
            }
            .padding(Spacing.medium)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(appLocalized("Cleanup Session Progress")))
        .accessibilityValue(Text("\(progress.reviewedCount) \(appLocalized("reviewed")), \(progress.remainingClusters) \(appLocalized("left to review"))"))
        .accessibilityHint(Text(appLocalized("Open next cluster to continue cleanup")))
    }

    private func metricItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: Spacing.xxSmall) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xSmall)
        .background(color.opacity(metricBackgroundOpacity), in: RoundedRectangle(cornerRadius: CornerRadius.small))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }

    private var metricBackgroundOpacity: Double {
        colorScheme == .dark ? ColorOpacity.statusBackgroundDark : ColorOpacity.statusBackground
    }
}

private struct CleanupCategoriesCard: View {
    let categories: [CleanupCategorySummary]
    let isLocked: (CleanupCategoryKind) -> Bool
    let onTapCategory: (CleanupCategorySummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(appLocalized("Cleanup Categories"))
                .font(.appHeadline)

            VStack(spacing: Spacing.small) {
                ForEach(categories) { category in
                    CleanupCategoryRow(
                        summary: category,
                        isLocked: isLocked(category.kind),
                        onTap: { onTapCategory(category) }
                    )
                }
            }
        }
        .padding(Spacing.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

private struct CleanupCategoryRow: View {
    let summary: CleanupCategorySummary
    let isLocked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.small) {
                Image(systemName: summary.kind.presentation.systemImageName)
                    .font(.title3)
                    .foregroundStyle(Color.accent)

                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(summary.kind.presentation.title)
                        .font(.appHeadline)
                    Text("\(summary.assetCount) items • \(ByteCountFormatter.string(fromByteCount: summary.estimatedSavingsBytes, countStyle: .file))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.small)
            .background(Color.secondary.opacity(ColorOpacity.statusBackground), in: RoundedRectangle(cornerRadius: CornerRadius.small))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(summary.kind.presentation.title))
        .accessibilityValue(Text("\(summary.assetCount)"))
        .accessibilityHint(
            Text(
                isLocked
                    ? summary.kind.presentation.lockedHint
                    : summary.kind.presentation.openHint
            )
        )
    }
}

private struct PremiumPaywallSheet: View {
    @Environment(\.dismiss) private var dismiss

    let feature: PremiumFeature

    var body: some View {
        RoutedNavigationStack {
            VStack(spacing: Spacing.large) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accent)

                VStack(spacing: Spacing.small) {
                    Text(title)
                        .font(.appTitle2)
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.appBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                PrimaryButton(appLocalized("Continue"), icon: "arrow.right") {
                    dismiss()
                }

                Spacer()
            }
            .padding(Spacing.large)
            .navigationTitle(Text(appLocalized("Premium")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text(appLocalized("Close")))
                }
            }
        }
    }

    private var title: String {
        switch feature {
        case .cleanupReminders:
            appLocalized("Custom reminder schedule is a premium feature")
        case .screenshotCleanup, .blurredPhotoCleanup:
            feature.categoryKind?.presentation.paywallTitle ?? ""
        }
    }

    private var message: String {
        switch feature {
        case .cleanupReminders:
            appLocalized("Unlock custom reminder timing to choose the day and time that fits your cleanup routine.")
        case .screenshotCleanup, .blurredPhotoCleanup:
            feature.categoryKind?.presentation.paywallMessage ?? ""
        }
    }
}

private struct ClusterReviewBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let status: ClusterReviewStatus

    var body: some View {
        Label(statusTitle, systemImage: iconName)
            .font(.caption2.bold())
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.xxSmall)
            .background(badgeMaterial, in: Capsule())
            .accessibilityLabel(Text(statusTitle))
            .accessibilityHint(Text(appLocalized("Cluster review status")))
    }

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

    private var iconName: String {
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

    private var foregroundColor: Color {
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

    private var badgeMaterial: Material {
        colorScheme == .dark ? .thickMaterial : .regularMaterial
    }
}

private struct RescanPromptCard: View {
    let onRescan: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.medium) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.statusNeedsReview)

            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(appLocalized("Gallery changed since your last scan"))
                    .font(.appHeadline)
                Text(appLocalized("Run a rescan to refresh clusters and review the latest changes"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.small)

            Button(appLocalized("Rescan"), action: onRescan)
                .buttonStyle(.borderedProminent)
                .tint(Color.statusNeedsReview)
        }
        .padding(Spacing.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

private struct ClusterSectionCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let badgeText: String
    let clusters: [PhotoCluster]
    let gridColumns: Int
    let reviewStatus: (UUID) -> ClusterReviewStatus
    let resurfacingState: (UUID) -> ClusterResurfacingState?
    let onOpenCluster: (PhotoCluster) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Text(title)
                    .font(.appHeadline)
                Text(badgeText)
                    .font(.caption.bold())
                    .foregroundStyle(colorScheme == .dark ? .primary : .secondary)
                    .padding(.horizontal, Spacing.xSmall)
                    .padding(.vertical, Spacing.xxSmall)
                    .background(Color.secondary.opacity(sectionBadgeOpacity), in: Capsule())
                Spacer()
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.small), count: gridColumns),
                spacing: Spacing.small
            ) {
                ForEach(clusters) { cluster in
                    ClusterCard(
                        cluster: cluster,
                        gridColumns: gridColumns,
                        reviewStatus: reviewStatus(cluster.id),
                        resurfacingState: resurfacingState(cluster.id),
                        onOpen: {
                            onOpenCluster(cluster)
                        }
                    )
                }
            }
        }
    }

    private var sectionBadgeOpacity: Double {
        colorScheme == .dark ? ColorOpacity.statusBackgroundDark : ColorOpacity.statusBackground
    }
}

private struct ClusterResurfacingBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let state: ClusterResurfacingState

    var body: some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.xxSmall)
            .background(colorScheme == .dark ? .thickMaterial : .regularMaterial, in: Capsule())
            .accessibilityLabel(Text(title))
            .accessibilityHint(Text(accessibilityHint))
    }

    private var title: String {
        switch state {
        case .unchanged:
            appLocalized("Unchanged")
        case .new:
            appLocalized("New")
        case .changed:
            appLocalized("Changed")
        }
    }

    private var color: Color {
        switch state {
        case .unchanged:
            colorScheme == .dark ? .primary.opacity(0.85) : .secondary
        case .new:
            .statusNew
        case .changed:
            .statusNeedsReview
        }
    }

    private var accessibilityHint: String {
        switch state {
        case .unchanged:
            appLocalized("Previously reviewed cluster with no significant changes")
        case .new:
            appLocalized("New cluster found after the latest rescan")
        case .changed:
            appLocalized("Previously reviewed cluster changed and needs your review again")
        }
    }
}

// MARK: - Preview
#Preview("Idle") {
    @Previewable @State var gridColumns = 2
    @Previewable @State var sensitivity = SensitivityLevel.medium
    
    let mockAnalysisService = MockPhotoAnalysisService()
    let mockRepository = MockPhotoClusterRepository()
    let viewModel = ScannerViewModel(
        analysisService: mockAnalysisService,
        repository: mockRepository
    )
    
    return ScannerView(
        gridColumns: $gridColumns,
        sensitivity: $sensitivity,
        viewModel: viewModel
    )
}

#Preview("Scanning") {
    @Previewable @State var gridColumns = 2
    @Previewable @State var sensitivity = SensitivityLevel.medium
    
    let mockAnalysisService = MockPhotoAnalysisService()
    let mockRepository = MockPhotoClusterRepository()
    let viewModel = ScannerViewModel(
        analysisService: mockAnalysisService,
        repository: mockRepository
    )
    viewModel.state = .scanning(progress: 0.6)
    
    return ScannerView(
        gridColumns: $gridColumns,
        sensitivity: $sensitivity,
        viewModel: viewModel
    )
}

#Preview("Results") {
    @Previewable @State var gridColumns = 2
    @Previewable @State var sensitivity = SensitivityLevel.medium
    
    let mockAnalysisService = MockPhotoAnalysisService()
    let mockRepository = MockPhotoClusterRepository()
    let viewModel = ScannerViewModel(
        analysisService: mockAnalysisService,
        repository: mockRepository
    )
    viewModel.state = .results([.mock, .mock, .mock])
    
    return ScannerView(
        gridColumns: $gridColumns,
        sensitivity: $sensitivity,
        viewModel: viewModel
    )
}
