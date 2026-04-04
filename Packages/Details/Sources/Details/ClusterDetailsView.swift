import SwiftUI
import Photos
import Core
import DesignSystem

#if os(iOS)

/// Details screen showing all photos in a cluster
public struct ClusterDetailsView: View {
    let cluster: PhotoCluster
    private let onReviewStateChanged: (() -> Void)?
    @State private var viewModel: ClusterDetailsViewModel
    @State private var gridColumns: Int = 3
    @State private var selectedAsset: SelectedAsset?

    public init(cluster: PhotoCluster, onReviewStateChanged: (() -> Void)? = nil) {
        self.cluster = cluster
        self.onReviewStateChanged = onReviewStateChanged
        self._viewModel = State(initialValue: ClusterDetailsViewModel(cluster: cluster))
    }

    init(
        cluster: PhotoCluster,
        viewModel: ClusterDetailsViewModel,
        onReviewStateChanged: (() -> Void)? = nil
    ) {
        self.cluster = cluster
        self.onReviewStateChanged = onReviewStateChanged
        self._viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        let displayedAssets = viewModel.displayedAssets(from: cluster.assets)

        ScrollView {
            if cluster.assets.isEmpty {
                ContentUnavailableView {
                    Label(appLocalized("No Photos Available"), systemImage: "photo")
                }
                .padding(.top, 80)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.small), count: gridColumns),
                    spacing: Spacing.small
                ) {
                    ForEach(displayedAssets, id: \.localIdentifier) { asset in
                        SelectablePhotoThumbnail(
                            asset: asset,
                            isBestShot: viewModel.isBestShot(asset.localIdentifier),
                            isSelected: viewModel.isSelected(asset.localIdentifier),
                            onToggleSelection: {
                                viewModel.toggleSelection(for: asset.localIdentifier)
                            },
                            onOpenOriginal: {
                                if let index = cluster.assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
                                    selectedAsset = SelectedAsset(asset: asset, index: index)
                                }
                            }
                        )
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.94).combined(with: .opacity),
                                removal: .scale(scale: 0.94).combined(with: .opacity)
                            )
                        )
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.bottom, Spacing.medium)
            }
        }
        .animation(.appSmooth, value: displayedAssets.map(\.localIdentifier))
        .animation(.appInteractive, value: viewModel.selectedAssetIDs)
        .animation(.appInteractive, value: viewModel.reviewStatus)
        .sensoryFeedback(.selection, trigger: viewModel.selectedAssetIDs.count)
        .sensoryFeedback(.success, trigger: viewModel.reviewStatus == .reviewed)
        .safeAreaInset(edge: .top) {
            VStack(spacing: Spacing.small) {
                ClusterReviewSummaryCard(
                    bestShotLabel: viewModel.bestShotLabel,
                    selectedCount: viewModel.selectedCount,
                    estimatedSavingsText: viewModel.estimatedSavingsText,
                    reviewStatus: viewModel.reviewStatus
                )

                if viewModel.isActionBarVisible {
                    ClusterReviewActionBar(
                        onKeepBestOnly: viewModel.keepBestOnly,
                        onSelectAllExceptBest: viewModel.selectAllExceptBest,
                        onClearSelection: viewModel.clearSelection
                    )
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.top, Spacing.small)
            .padding(.bottom, Spacing.medium)
            .background(.regularMaterial)
        }
        .navigationTitle(Text(appLocalized("Similar Photos")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $gridColumns) {
                        ForEach(2...4, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    } label: {
                        Text(appLocalized("Columns"))
                    }
                } label: {
                    Image(systemName: "square.grid.3x2")
                }
            }
        }
        .fullScreenCover(item: $selectedAsset) { selection in
            FullscreenPhotoPagerView(assets: cluster.assets, selectedIndex: selection.index)
        }
        .task {
            await viewModel.load()
        }
        .onDisappear {
            onReviewStateChanged?()
        }
    }
}

private struct SelectedAsset: Identifiable {
    let asset: PHAsset
    let index: Int
    var id: String { asset.localIdentifier }
}

struct SelectablePhotoThumbnail: View {
    let asset: PHAsset
    let isBestShot: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onOpenOriginal: () -> Void

    @State private var image: UIImage?
    @State private var showingMetadata = false

    var body: some View {
        Button(action: onToggleSelection) {
            ZStack {
                Color.clear

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0)
                        .clipped()
                        .aspectRatio(16/9, contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(ColorOpacity.placeholderFill))
                        .frame(height: 120)
                        .overlay {
                            ProgressView()
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) {
                if isBestShot {
                    Label(appLocalized("Best Shot"), systemImage: "star.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, Spacing.xSmall)
                        .padding(.vertical, Spacing.xxSmall)
                        .background(.regularMaterial, in: Capsule())
                        .padding(Spacing.xSmall)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, Color.accent)
                        .padding(Spacing.xSmall)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: CornerRadius.small)
                        .fill(Color.accent.opacity(ColorOpacity.selectionOverlay))
                        .transition(.opacity)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.small)
                    .stroke(borderColor, lineWidth: borderLineWidth)
            }
            .animation(.appInteractiveFast, value: isSelected)
            .animation(.appInteractiveFast, value: isBestShot)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .cornerRadius(CornerRadius.small)
        .contextMenu {
            Button {
                showingMetadata = true
            } label: {
                Label {
                    Text(appLocalized("Show Info"))
                } icon: {
                    Image(systemName: "info.circle")
                }
            }
            
            Button {
                onOpenOriginal()
            } label: {
                Label {
                    Text(appLocalized("Open Original"))
                } icon: {
                    Image(systemName: "arrow.up.right.square")
                }
            }
        }
        .sheet(isPresented: $showingMetadata) {
            MetadataView(metadata: asset.displayMetadata)
                .presentationDetents([.medium])
        }
        .task {
            image = try? await asset.loadImage(targetSize: CGSize(width: 300, height: 300))
        }
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var borderColor: Color {
        if isBestShot {
            return .heroGold.opacity(0.9)
        }
        if isSelected {
            return .accent
        }
        return .clear
    }

    private var borderLineWidth: CGFloat {
        (isBestShot || isSelected) ? 2 : 0
    }

    private var accessibilityLabel: String {
        if isBestShot {
            return appLocalized("Best Shot")
        }
        if isSelected {
            return appLocalized("Selected for cleanup review")
        }
        return appLocalized("Not selected")
    }
}

// MARK: - Fullscreen Photo View
private struct FullscreenPhotoPagerView: View {
    let assets: [PHAsset]
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(assets: [PHAsset], selectedIndex: Int) {
        self.assets = assets
        self._currentIndex = State(initialValue: selectedIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(assets.indices, id: \.self) { index in
                    ZoomablePhotoView(asset: assets[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding()
            }
            .accessibilityLabel(Text(appLocalized("Close")))
        }
    }
}

private struct ZoomablePhotoView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(zoomGesture)
                        .gesture(
                            panGesture(in: proxy.size),
                            including: scale > 1 ? .all : .subviews
                        )
                } else if isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .task(id: asset.localIdentifier) {
            defer { isLoading = false }
            image = try? await asset.loadImage(targetSize: PHImageManagerMaximumSize)
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                let newScale = scale * delta
                scale = min(max(newScale, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale <= minScale {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = minScale
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, in: size)
            }
            .onEnded { _ in
                guard scale > 1 else {
                    offset = .zero
                    lastOffset = .zero
                    return
                }
                lastOffset = offset
            }
    }

    private func clampedOffset(_ proposed: CGSize, in size: CGSize) -> CGSize {
        ZoomingHelpers.clampedOffset(proposed, in: size, scale: scale)
    }
}

// MARK: - Metadata View
struct MetadataView: View {
    let metadata: AssetMetadata
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent {
                        Text(metadata.resolution)
                    } label: {
                        Text(appLocalized("Resolution"))
                    }
                    
                    LabeledContent {
                        Text(metadata.formattedCreationDate)
                    } label: {
                        Text(appLocalized("Created"))
                    }
                    
                    LabeledContent {
                        Text(metadata.isFavorite ? appLocalized("Yes") : appLocalized("No"))
                    } label: {
                        Text(appLocalized("Favorite"))
                    }
                } header: {
                    Text(appLocalized("Details"))
                }
            }
            .navigationTitle(Text(appLocalized("Photo Info")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text(appLocalized("Done"))
                    }
                }
            }
        }
    }
}

#else

public struct ClusterDetailsView: View {
    let cluster: PhotoCluster

    public init(cluster: PhotoCluster, onReviewStateChanged: (() -> Void)? = nil) {
        self.cluster = cluster
    }

    public var body: some View {
        ContentUnavailableView {
            Label(appLocalized("Similar Photos"), systemImage: "photo.stack")
        } description: {
            Text(appLocalized("Cluster details are available on iOS."))
        }
    }
}

struct MetadataView: View {
    var body: some View {
        EmptyView()
    }
}

#endif

// MARK: - Preview
#Preview {
    NavigationStack {
        ClusterDetailsView(cluster: .mock)
    }
}
