import SwiftUI
import Photos
import Core
import DesignSystem

#if os(iOS)

/// Paging fullscreen photo viewer shared by Similar Photos and category cleanup.
struct FullscreenPhotoPagerView: View {
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
                    FullscreenZoomablePhotoView(asset: assets[index])
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
            .accessibilityLabel(Text(DetailsL10n.Common.close))
        }
    }
}

/// Zoomable fullscreen photo shared by the Similar Photos and category cleanup pagers.
struct FullscreenZoomablePhotoView: View {
    let asset: PHAsset
    /// Shown in place of the asset's own image while it is set — how the
    /// enhancement preview reuses this viewer, zoom and pan included. The
    /// asset keeps loading underneath, so comparing is instant.
    var overrideImage: CGImage?

    @Environment(\.displayScale) private var displayScale

    @State private var image: UIImage?
    @State private var imageLoadState = PhotoImageLoadState()
    @State private var imageLoadAttempt = 0
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0

    var body: some View {
        GeometryReader { proxy in
            let targetSize = PhotoFullscreenImageSizePolicy.targetSize(
                viewportSize: proxy.size,
                displayScale: displayScale,
                maximumZoomScale: maxScale
            )

            ZStack {
                if let overrideImage {
                    Image(decorative: overrideImage, scale: 1)
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
                        .accessibilityLabel(Text(DetailsL10n.ClusterDetails.enhancementPreviewTitle))
                } else if let image {
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
                        .accessibilityLabel(Text(DetailsL10n.Common.photoPreview))
                } else if imageLoadState.phase == .failed {
                    FullscreenPhotoLoadFailureView {
                        imageLoadAttempt += 1
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel(Text(DetailsL10n.Common.loadingPhotoPreview))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .task(id: imageLoadTaskID(for: targetSize)) {
                await loadImage(targetSize: targetSize)
            }
        }
    }

    /// Rebuilds the load when the asset, the requested size, or a manual retry changes.
    private func imageLoadTaskID(for targetSize: CGSize) -> String {
        "\(asset.localIdentifier)#\(Int(targetSize.width))x\(Int(targetSize.height))#\(imageLoadAttempt)"
    }

    @MainActor
    private func loadImage(targetSize: CGSize) async {
        image = nil
        let generation = imageLoadState.begin()
        do {
            guard let loadedImage = try await asset.loadImage(targetSize: targetSize) else {
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
                offset = ZoomingHelpers.clampedOffset(proposed, in: size, scale: scale)
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
}

/// Retry affordance for the black fullscreen pager, styled for a dark background regardless of
/// the system color scheme.
struct FullscreenPhotoLoadFailureView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.small) {
            Image(systemName: "icloud.slash")
                .font(.largeTitle)
                .accessibilityHidden(true)

            Text(DetailsL10n.Common.photoPreviewUnavailable)
                .font(.callout)
                .multilineTextAlignment(.center)

            Button(action: retry) {
                Label(DetailsL10n.FullscreenZoomablePhoto.retry, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .accessibilityHint(Text(DetailsL10n.FullscreenZoomablePhoto.tryLoadingThePhotoAgain))
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(Spacing.medium)
        .accessibilityElement(children: .contain)
    }
}

#endif
