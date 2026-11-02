import SwiftUI
import Photos
import Core
import DesignSystem

#if os(iOS)

struct SelectablePhotoThumbnail: View {
    let asset: PHAsset
    let thumbnailAspectRatio: CGFloat
    let isBestShot: Bool
    var bestShotConfidence: BestShotConfidence = .automatic
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onOpenOriginal: () -> Void
    var onMakeBestShot: (() -> Void)?
    var isEnhanced = false
    var enhancementState: PhotoEnhancementState = .unavailable
    var onEnhance: (() -> Void)?
    var onRevertEnhancement: (() -> Void)?
    /// Empty before iOS 27, where grids cannot host swipe actions.
    var swipeActions: [PhotoTileSwipeAction] = []
    var onSwipeAction: (PhotoTileSwipeAction) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var image: UIImage?
    @State private var imageLoadState = PhotoImageLoadState()
    @State private var imageLoadAttempt = 0
    @State private var showingMetadata = false

    var body: some View {
        ZStack {
            Button(action: onToggleSelection) {
                PhotoThumbnailAspectRatioLayout(aspectRatio: thumbnailAspectRatio) {
                    ZStack {
                        Color.secondary.opacity(ColorOpacity.placeholderFill)

                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else if imageLoadState.phase == .loading {
                            ProgressView()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(thumbnailShape)
                .overlay {
                    if isSelected {
                        thumbnailShape
                            .fill(Color.accent.opacity(ColorOpacity.selectionOverlay))
                            .transition(.opacity)
                    }
                }
                .overlay {
                    thumbnailShape
                        .stroke(borderColor, lineWidth: borderLineWidth)
                }
                .overlay(alignment: .topLeading) {
                    if isBestShot {
                        Label {
                            Text(bestShotConfidence.badgeTitle)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: bestShotConfidence.badgeSymbolName)
                                .foregroundStyle(Color.heroGold)
                        }
                            .font(.caption.bold())
                            .padding(.horizontal, Spacing.xSmall)
                            .padding(.vertical, Spacing.xxSmall)
                            .background(.regularMaterial, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(Color.heroGold.opacity(0.7), lineWidth: 1)
                            }
                            .padding(Spacing.xSmall)
                            .transition(bestShotBadgeTransition)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isEnhanced {
                        enhancedBadge
                            .padding(Spacing.xSmall)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .center) {
                    if enhancementState.isBusy {
                        ProgressView()
                            .padding(Spacing.small)
                            .background(.regularMaterial, in: Circle())
                    }
                }
                .animation(.appInteractiveFast, value: isEnhanced)
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accent)
                            .background(.white, in: Circle())
                            .padding(Spacing.xSmall)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .animation(.appInteractiveFast, value: isSelected)
                .animation(.appInteractiveFast, value: isBestShot)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityValue(Text(accessibilityValue))
            .accessibilityHint(Text(accessibilityHint))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityActions {
                // The rotor mirrors the swipe; Make Best Shot is already below.
                ForEach(swipeActions.filter { $0 != .makeBestShot }, id: \.self) { action in
                    Button(action.title) { onSwipeAction(action) }
                }
                if let onMakeBestShot, !isBestShot {
                    Button(DetailsL10n.ClusterDetails.makeBestShot, action: onMakeBestShot)
                }
                if isEnhanced, let onRevertEnhancement {
                    Button(DetailsL10n.ClusterDetails.revertToOriginal, action: onRevertEnhancement)
                } else if let onEnhance {
                    Button(DetailsL10n.ClusterDetails.enhance, action: onEnhance)
                }
            }

            if imageLoadState.phase == .failed {
                PhotoLoadFailureView {
                    imageLoadAttempt += 1
                }
                .background(.regularMaterial, in: thumbnailShape)
            }
        }
        .contentShape(.interaction, thumbnailShape)
        .contentShape(.contextMenuPreview, thumbnailShape)
        .photoTileSwipeActions(swipeActions, perform: onSwipeAction)
        .contextMenu {
            enhancementMenuItems

            if let onMakeBestShot, !isBestShot {
                Button {
                    onMakeBestShot()
                } label: {
                    Label {
                        Text(DetailsL10n.ClusterDetails.makeBestShot)
                    } icon: {
                        Image(systemName: "star")
                    }
                }
            }

            Button {
                showingMetadata = true
            } label: {
                Label {
                    Text(DetailsL10n.ClusterDetails.showInfo)
                } icon: {
                    Image(systemName: "info.circle")
                }
            }

            Button {
                onOpenOriginal()
            } label: {
                Label {
                    Text(DetailsL10n.ClusterDetails.openOriginal)
                } icon: {
                    Image(systemName: "arrow.up.forward.square")
                }
            }
        } preview: {
            contextMenuPreview
        }
        .sheet(isPresented: $showingMetadata) {
            MetadataView(asset: asset)
                .presentationDetents([.medium, .large])
        }
        .task(id: imageLoadTaskID) {
            await loadThumbnail()
        }
    }

    private var presentation: PhotoTilePresentation {
        PhotoTilePresentation(
            isBestShot: isBestShot,
            isSelected: isSelected,
            bestShotConfidence: bestShotConfidence
        )
    }

    private var borderColor: Color {
        presentation.borderColor
    }

    private var borderLineWidth: CGFloat {
        presentation.borderLineWidth
    }

    /// A settle-in fade rather than a pop when the measured ranking lands;
    /// under reduce motion the scale drops and only the fade remains.
    private var bestShotBadgeTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity)
    }

    private var thumbnailShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous)
    }

    private var thumbnailTargetSize: CGSize {
        PhotoTilePresentation.thumbnailTargetSize(aspectRatio: thumbnailAspectRatio)
    }

    private var imageLoadTaskID: String {
        PhotoTilePresentation.imageLoadTaskID(
            localIdentifier: asset.localIdentifier,
            modificationDate: asset.modificationDate,
            attempt: imageLoadAttempt
        )
    }

    @MainActor
    private func loadThumbnail() async {
        image = nil
        let generation = imageLoadState.begin()
        do {
            guard let loadedImage = try await asset.loadImage(targetSize: thumbnailTargetSize) else {
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

    private var contextMenuPreview: some View {
        ZStack {
            Color.secondary.opacity(ColorOpacity.placeholderFill)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if imageLoadState.phase == .loading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: contextMenuPreviewWidth,
            height: contextMenuPreviewWidth / thumbnailAspectRatio
        )
        .clipShape(thumbnailShape)
    }

    private var contextMenuPreviewWidth: CGFloat { 240 }

    /// One step in each direction: enhance, or put the original back.
    @ViewBuilder
    private var enhancementMenuItems: some View {
        if isEnhanced, let onRevertEnhancement {
            Button(action: onRevertEnhancement) {
                Label {
                    Text(DetailsL10n.ClusterDetails.revertToOriginal)
                } icon: {
                    Image(systemName: "arrow.uturn.backward")
                }
            }
            .disabled(enhancementState.isBusy)
        } else if let onEnhance {
            Button(action: onEnhance) {
                Label {
                    Text(DetailsL10n.ClusterDetails.enhance)
                } icon: {
                    Image(systemName: "wand.and.stars")
                }
            }
            .disabled(enhancementState.isBusy)
        }
    }

    /// Permanent marker that this photo is showing Alike's enhanced version.
    private var enhancedBadge: some View {
        Label {
            Text(DetailsL10n.ClusterDetails.enhanced)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(Color.accent)
        }
        .font(.caption2.bold())
        .padding(.horizontal, Spacing.xSmall)
        .padding(.vertical, Spacing.xxSmall)
        .background(.regularMaterial, in: Capsule())
    }

    private var accessibilityLabel: String {
        presentation.accessibilityLabel
    }

    private var accessibilityValue: String {
        presentation.accessibilityValue
    }

    private var accessibilityHint: String {
        presentation.accessibilityHint
    }
}

#else

struct SelectablePhotoThumbnail: View {
    var body: some View {
        EmptyView()
    }
}

#endif
