import SwiftUI
import Core
import DesignSystem

struct ALIComparisonReviewPresentation: Equatable {
    let animationURL: URL?
    let playback: OverlayAnimationPlayback
    let ambientMotion: AnimatedImageAmbientMotion

    static func isEligible(assetCount: Int) -> Bool {
        assetCount > 1
    }

    static func resolve(isVisible: Bool, scenePhase: ScenePhase) -> Self {
        let isMotionEnabled = isVisible && scenePhase == .active

        return Self(
            animationURL: isMotionEnabled ? ALIAssets.comparisonReviewOverlayURL : nil,
            playback: .loop,
            ambientMotion: isMotionEnabled ? .breathe : .none
        )
    }

    static func imageURL(for displayScale: CGFloat) -> URL {
        ALIAssets.comparisonReviewURL(for: imageScale(for: displayScale))
    }

    private static func imageScale(for displayScale: CGFloat) -> ALIAssets.ComparisonReviewScale {
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

struct ALIComparisonReviewView: View {
    private enum Constants {
        static let maximumWidth: CGFloat = 72
    }

    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        AnimatedImageOverlay(
            animationURL: presentation.animationURL,
            aspectRatio: 1,
            maximumWidth: Constants.maximumWidth,
            playback: presentation.playback,
            ambientMotion: presentation.ambientMotion
        ) {
            comparisonImage
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(appLocalized("ALI comparing similar photos")))
        .onAppear {
            setVisibility(true)
        }
        .onDisappear {
            setVisibility(false)
        }
    }

    @ViewBuilder
    private var comparisonImage: some View {
        let imageURL = ALIComparisonReviewPresentation.imageURL(for: displayScale)

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
        Image(systemName: "rectangle.on.rectangle.angled")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Color.accent)
            .padding(Spacing.xxLarge)
    }

    private var presentation: ALIComparisonReviewPresentation {
        .resolve(isVisible: isVisible, scenePhase: scenePhase)
    }

    private func setVisibility(_ isVisible: Bool) {
        self.isVisible = isVisible
    }
}
