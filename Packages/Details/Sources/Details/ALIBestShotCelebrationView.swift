import SwiftUI
import Core
import DesignSystem

struct ALIBestShotCelebrationPresentation: Equatable {
    let animationURL: URL?
    let playback: OverlayAnimationPlayback
    let ambientMotion: AnimatedImageAmbientMotion

    static func resolve(isVisible: Bool, scenePhase: ScenePhase) -> Self {
        let isMotionEnabled = isVisible && scenePhase == .active

        return Self(
            animationURL: isMotionEnabled ? ALIAssets.bestShotOverlayURL : nil,
            playback: .loop,
            ambientMotion: isMotionEnabled ? .breathe : .none
        )
    }

    static func imageURL(for displayScale: CGFloat) -> URL {
        ALIAssets.bestShotURL(for: imageScale(for: displayScale))
    }

    private static func imageScale(for displayScale: CGFloat) -> ALIAssets.BestShotScale {
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

struct ALIBestShotCelebrationView: View {
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
            bestShotImage
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(appLocalized("ALI celebrating the Best Shot")))
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
    }

    @ViewBuilder
    private var bestShotImage: some View {
        let imageURL = ALIBestShotCelebrationPresentation.imageURL(for: displayScale)

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
        Image(systemName: "crown.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Color.accent)
            .padding(Spacing.xxLarge)
    }

    private var presentation: ALIBestShotCelebrationPresentation {
        .resolve(isVisible: isVisible, scenePhase: scenePhase)
    }
}
