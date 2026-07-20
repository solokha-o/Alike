import SwiftUI
import Core
import DesignSystem

struct ALICleanupProgressPresentation: Equatable {
    let animationURL: URL?
    let playback: OverlayAnimationPlayback
    let ambientMotion: AnimatedImageAmbientMotion

    static func resolve(
        isExecuting: Bool,
        isVisible: Bool,
        scenePhase: ScenePhase
    ) -> Self {
        let isMotionEnabled = isExecuting && isVisible && scenePhase == .active

        return Self(
            animationURL: isMotionEnabled ? ALIAssets.cleanupProgressOverlayURL : nil,
            playback: .loop,
            ambientMotion: .none
        )
    }

    static func imageURL(for displayScale: CGFloat) -> URL {
        ALIAssets.cleanupProgressURL(for: imageScale(for: displayScale))
    }

    private static func imageScale(for displayScale: CGFloat) -> ALIAssets.CleanupProgressScale {
        switch displayScale {
        case ..<1.5:
            .oneX
        case ..<2.5:
            .twoX
        default:
            .threeX
        }
    }
}

struct ALICleanupProgressView: View {
    private enum Constants {
        static let maximumArtworkWidth: CGFloat = 260
    }

    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    let selectedCount: Int
    let estimatedSavingsText: String
    let isExecuting: Bool

    var body: some View {
        VStack(spacing: Spacing.medium) {
            Text(appLocalized("Organizing Photos"))
                .font(.appTitle2)
                .multilineTextAlignment(.center)

            metrics

            AnimatedImageOverlay(
                animationURL: presentation.animationURL,
                aspectRatio: 1,
                maximumWidth: Constants.maximumArtworkWidth,
                playback: presentation.playback,
                ambientMotion: presentation.ambientMotion
            ) {
                cleanupImage
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(appLocalized("ALI organizing selected photos")))
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.large)
        .background(
            Color.secondary.opacity(ColorOpacity.placeholderFill),
            in: RoundedRectangle(cornerRadius: CornerRadius.medium)
        )
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
    }

    @ViewBuilder
    private var metrics: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Spacing.small) {
                selectedMetric
                savingsMetric
            }
        } else {
            HStack(alignment: .top, spacing: Spacing.large) {
                selectedMetric
                savingsMetric
            }
        }
    }

    private var selectedMetric: some View {
        metric(
            title: appLocalized("Selected Photos"),
            value: "\(selectedCount)"
        )
    }

    private var savingsMetric: some View {
        metric(
            title: appLocalized("Estimated Savings"),
            value: estimatedSavingsText
        )
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: Spacing.xxSmall) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(.appHeadline)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var cleanupImage: some View {
        let imageURL = ALICleanupProgressPresentation.imageURL(for: displayScale)

#if canImport(UIKit)
        if let image = UIImage(contentsOfFile: imageURL.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            fallbackImage
        }
#elseif canImport(AppKit)
        if let image = NSImage(contentsOf: imageURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            fallbackImage
        }
#endif
    }

    private var fallbackImage: some View {
        Image(systemName: "square.stack.3d.up")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Color.accent)
            .padding(Spacing.xxLarge)
    }

    private var presentation: ALICleanupProgressPresentation {
        .resolve(
            isExecuting: isExecuting,
            isVisible: isVisible,
            scenePhase: scenePhase
        )
    }
}
