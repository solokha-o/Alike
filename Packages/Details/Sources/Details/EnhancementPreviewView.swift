import Core
import DesignSystem
import Photos
import SwiftUI

#if os(iOS)

/// Before/after preview of the auto-enhancement.
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

    @State private var originalImage: UIImage?
    @GestureState private var isShowingOriginal = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.medium) {
                comparison
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(isShowingOriginal
                     ? DetailsL10n.Common.bestShot
                     : DetailsL10n.ClusterDetails.enhancementPreviewTitle)
                    .font(.appCallout.weight(.semibold))
                    .accessibilityHidden(true)

                Text(DetailsL10n.ClusterDetails.holdToCompare)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Spacing.medium)
            .navigationTitle(Text(DetailsL10n.ClusterDetails.enhancementPreviewTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DetailsL10n.Common.cancel) {
                        onCancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(DetailsL10n.ClusterDetails.applyEnhancement) {
                        onApply()
                        dismiss()
                    }
                    .disabled(enhancedImage == nil || state.isBusy)
                }
            }
        }
        .task(id: asset.localIdentifier) {
            originalImage = try? await asset.loadImage(targetSize: CGSize(width: 1_200, height: 1_200))
        }
    }

    @ViewBuilder
    private var comparison: some View {
        ZStack {
            Color.secondary.opacity(ColorOpacity.placeholderFill)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))

            if isShowingOriginal, let originalImage {
                Image(uiImage: originalImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let enhancedImage {
                Image(decorative: enhancedImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .gesture(
            LongPressGesture(minimumDuration: 0.05)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .updating($isShowingOriginal) { value, state, _ in
                    switch value {
                    case .second(true, _):
                        state = true
                    default:
                        state = false
                    }
                }
        )
        .accessibilityLabel(Text(DetailsL10n.ClusterDetails.enhancementPreviewTitle))
    }
}

#endif
