import Core
import DesignSystem
import Photos
import SwiftUI

#if os(iOS)

/// Before/after preview of the auto-enhancement, in the same fullscreen viewer
/// the rest of the screen uses — same zoom, same pan, same black canvas.
///
/// Nothing here writes to the photo library: the user sees the result first and
/// only then applies it, and can always leave without changing anything.
struct EnhancementPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let asset: PHAsset
    let enhancedImage: CGImage?
    let state: PhotoEnhancementState
    let onApply: () -> Void
    let onCancel: () -> Void

    @GestureState private var isShowingOriginal = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            FullscreenZoomablePhotoView(
                asset: asset,
                overrideImage: isShowingOriginal ? nil : enhancedImage
            )
            .ignoresSafeArea()

            stateLabel
        }
        .safeAreaInset(edge: .bottom) { actions }
        .overlay {
            if state.isBusy && enhancedImage == nil {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel(Text(DetailsL10n.ClusterDetails.enhancementPreviewTitle))
            }
        }
    }

    private var stateLabel: some View {
        Text(isShowingOriginal
             ? DetailsL10n.ClusterDetails.originalPhoto
             : DetailsL10n.ClusterDetails.enhancementPreviewTitle)
            .font(.appCallout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.xxSmall)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, Spacing.small)
            .animation(.appInteractiveFast, value: isShowingOriginal)
    }

    private var actions: some View {
        HStack(spacing: Spacing.medium) {
            Button(DetailsL10n.Common.cancel) {
                onCancel()
                dismiss()
            }
            .buttonStyle(.bordered)
            // Only the plain controls take the white tint. A prominent button
            // tinted white paints a white label on a white background.
            .tint(.white)

            compareButton
                .layoutPriority(-1)

            Button {
                onApply()
                dismiss()
            } label: {
                Text(DetailsL10n.ClusterDetails.applyEnhancement)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .disabled(enhancedImage == nil || state.isBusy)
            .opacity(enhancedImage == nil || state.isBusy ? 0.6 : 1)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    /// Held rather than toggled: comparing is a glance, not a mode. The gesture
    /// lives on the button so it never fights the viewer's zoom and pan.
    private var compareButton: some View {
        Label {
            Text(DetailsL10n.ClusterDetails.holdToCompare)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        } icon: {
            Image(systemName: "arrow.left.arrow.right.circle")
        }
        .font(.appCaption)
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xxSmall)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isShowingOriginal) { _, state, _ in
                    state = true
                }
        )
        .accessibilityAddTraits(.isButton)
        .disabled(enhancedImage == nil)
    }
}

#endif
