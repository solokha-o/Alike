import SwiftUI
import Core
import DesignSystem
import Details
import Photos

/// Scanner screen with analysis and results
public struct ScannerView: View {
    @State private var viewModel: ScannerViewModel
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
        }
        .task {
            await viewModel.loadCachedResults()
            
            // Check if gallery changed
            if await viewModel.checkForGalleryChanges() {
                // Show rescan suggestion (simplified for MVP)
            }
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
        let sessionProgress = viewModel.sessionProgress(for: sortedClusters)

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
                    CleanupSessionProgressCard(progress: sessionProgress)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.small), count: gridColumns), spacing: Spacing.small) {
                        ForEach(sortedClusters) { cluster in
                            ClusterCard(
                                cluster: cluster,
                                reviewStatus: viewModel.reviewStatus(for: cluster.id),
                                onReviewStateChanged: {
                                    Task {
                                        await viewModel.loadReviewStates()
                                    }
                                }
                            )
                        }
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
    let reviewStatus: ClusterReviewStatus
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
                        .frame(height: 150)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0)
                        .clipped()
                        .aspectRatio(16/9, contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 150)
                        .overlay {
                            ProgressView()
                        }
                }
#else
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 150)
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
            .cornerRadius(CornerRadius.medium)
            .subtleShadow()
        }
#if os(iOS)
        .task {
            if let asset = cluster.thumbnail {
                thumbnailImage = try? await asset.loadImage()
            }
        }
#endif
    }
}

private struct CleanupSessionProgressCard: View {
    let progress: CleanupSessionProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(appLocalized("Cleanup Session Progress"))
                .font(.appHeadline)

            HStack(spacing: Spacing.small) {
                statusItem(title: appLocalized("Reviewed"), value: progress.reviewedCount, color: .green)
                statusItem(title: appLocalized("In review"), value: progress.inReviewCount, color: .accent)
                statusItem(title: appLocalized("Not reviewed"), value: progress.notReviewedCount, color: .secondary)
            }

            Divider()

            HStack {
                Text(appLocalized("Reviewed Clusters: \(progress.reviewedCount) of \(progress.totalClusters)"))
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(progress.reviewedPercent)%")
                    .font(.appHeadline)
                    .monospacedDigit()
            }

            HStack {
                Text(appLocalized("Estimated Savings Reviewed So Far"))
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: progress.reviewedSavingsBytes, countStyle: .file))
                    .font(.appBody.bold())
                    .monospacedDigit()
            }
        }
        .padding(Spacing.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private func statusItem(title: String, value: Int, color: Color) -> some View {
        VStack(spacing: Spacing.xxSmall) {
            Text("\(value)")
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
        case .inReview:
            .accent
        case .reviewed:
            .green
        }
    }
}

// MARK: - Preview
#Preview("Idle") {
    @Previewable @State var gridColumns = 3
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
    @Previewable @State var gridColumns = 3
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
    @Previewable @State var gridColumns = 3
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
