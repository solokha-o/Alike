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
                    .stroke(Color.accent.opacity(0.2), lineWidth: 8)
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
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: cardHeight)
                        .overlay {
                            ProgressView()
                        }
                }
#else
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
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
}

private struct CleanupSessionProgressCard: View {
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
                    metricItem(title: appLocalized("Needs review"), value: "\(progress.needsReReviewCount)", color: .orange)
                    metricItem(title: appLocalized("Reviewed"), value: "\(progress.reviewedCount)", color: .green)
                }

                HStack(spacing: Spacing.small) {
                    metricItem(title: appLocalized("Left to Review"), value: "\(progress.remainingClusters)", color: .accent)
                    metricItem(title: appLocalized("In review"), value: "\(progress.inReviewCount)", color: .blue)
                    metricItem(title: appLocalized("Not reviewed"), value: "\(progress.notReviewedCount)", color: .secondary)
                }

                HStack(spacing: Spacing.small) {
                    metricItem(title: appLocalized("Total Selected Items"), value: "\(progress.totalSelectedItems)", color: .accent)
                    metricItem(
                        title: appLocalized("Estimated Savings"),
                        value: ByteCountFormatter.string(fromByteCount: progress.reviewedSavingsBytes, countStyle: .file),
                        color: .mint
                    )
                }
            }
            .padding(Spacing.medium)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
        .buttonStyle(.plain)
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
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: CornerRadius.small))
    }
}

private struct ClusterReviewBadge: View {
    let status: ClusterReviewStatus

    var body: some View {
        Label(statusTitle, systemImage: iconName)
            .font(.caption2.bold())
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.xxSmall)
            .background(.regularMaterial, in: Capsule())
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
            .secondary
        case .needsReReview:
            .orange
        case .inReview:
            .accent
        case .reviewed:
            .green
        }
    }
}

private struct RescanPromptCard: View {
    let onRescan: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.medium) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)

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
                .tint(.orange)
        }
        .padding(Spacing.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

private struct ClusterSectionCard: View {
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
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.xSmall)
                    .padding(.vertical, Spacing.xxSmall)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
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
}

private struct ClusterResurfacingBadge: View {
    let state: ClusterResurfacingState

    var body: some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.xxSmall)
            .background(.regularMaterial, in: Capsule())
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
            .secondary
        case .new:
            .mint
        case .changed:
            .orange
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
