import SwiftUI
import Core
import DesignSystem
import Details
import Photos
import Cleanup

/// Scanner screen with analysis and results
public struct ScannerView: View {
    @State private var viewModel: ScannerViewModel
    @State private var summaryEntryCluster: PhotoCluster?
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
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle:
                    idleView
                case .scanning(let progress):
                    scanningView(progress: progress)
                case .results(let clusters):
                    resultsView(clusters: clusters)
                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle(Text(appLocalized("Scanner")))
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .navigationDestination(item: $summaryEntryCluster) { cluster in
                ClusterDetailsView(
                    cluster: cluster,
                    onReviewStateChanged: {
                        Task {
                            await viewModel.loadReviewStates()
                        }
                    }
                )
            }
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
    private func resultsView(clusters: [PhotoCluster]) -> some View {
        let sortedClusters = viewModel.sortedClusters(from: clusters)
        let needsReviewClusters = viewModel.needsReviewClusters(from: sortedClusters)
        let remainingClusters = viewModel.remainingClusters(from: sortedClusters)
        let sessionProgress = viewModel.displayedSessionProgress(for: sortedClusters)

        return ScrollView {
            if sortedClusters.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text(appLocalized("No Similar Photos Found"))
                    } icon: {
                        Image(systemName: "photo.stack")
                    }
                } description: {
                    Text(appLocalized("Try adjusting sensitivity in Settings"))
                }
                .padding(.top, 100)
            } else {
                VStack(spacing: Spacing.medium) {
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
                            onReviewStateChanged: {
                                Task {
                                    await viewModel.loadReviewStates()
                                }
                            }
                        )
                    }

                    CleanupSessionProgressCard(
                        progress: sessionProgress,
                        onTap: {
                            summaryEntryCluster = viewModel.cleanupEntryCluster(from: sortedClusters)
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
                            onReviewStateChanged: {
                                Task {
                                    await viewModel.loadReviewStates()
                                }
                            }
                        )
                    }
                }
                .padding(Spacing.medium)
            }
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

// MARK: - Cluster Card
struct ClusterCard: View {
    let cluster: PhotoCluster
    let gridColumns: Int
    let reviewStatus: ClusterReviewStatus
    let resurfacingState: ClusterResurfacingState?
    let onReviewStateChanged: (() -> Void)?
#if os(iOS)
    @State private var thumbnailImage: UIImage?
#endif
    
    var body: some View {
        NavigationLink {
            ClusterDetailsView(
                cluster: cluster,
                onReviewStateChanged: onReviewStateChanged
            )
        } label: {
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
    let onReviewStateChanged: () -> Void

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
                        onReviewStateChanged: onReviewStateChanged
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
