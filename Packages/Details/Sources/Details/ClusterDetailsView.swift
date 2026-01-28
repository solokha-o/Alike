import SwiftUI
import Photos
import Core
import DesignSystem

/// Details screen showing all photos in a cluster
public struct ClusterDetailsView: View {
    let cluster: PhotoCluster
    @State private var gridColumns: Int = 3
    @State private var selectedAsset: SelectedAsset?
    @Environment(\.dismiss) private var dismiss
    
    public init(cluster: PhotoCluster) {
        self.cluster = cluster
    }
    
    public var body: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.small), count: gridColumns),
                spacing: Spacing.small
            ) {
                ForEach(cluster.assets, id: \.localIdentifier) { asset in
                    PhotoThumbnail(asset: asset) {
                        if let index = cluster.assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
                            selectedAsset = SelectedAsset(asset: asset, index: index)
                        }
                    }
                }
            }
            .padding(Spacing.medium)
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
    }
}

private struct SelectedAsset: Identifiable {
    let asset: PHAsset
    let index: Int
    var id: String { asset.localIdentifier }
}

// MARK: - Photo Thumbnail
struct PhotoThumbnail: View {
    let asset: PHAsset
    let onOpenOriginal: () -> Void
    @State private var image: UIImage?
    @State private var showingMetadata = false
    
    var body: some View {
        Group {
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
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 120)
                    .overlay {
                        ProgressView()
                    }
            }
        }
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
        let maxX = (size.width * (scale - 1)) / 2
        let maxY = (size.height * (scale - 1)) / 2
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
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

// MARK: - Preview
#Preview {
    NavigationStack {
        ClusterDetailsView(cluster: .mock)
    }
}
