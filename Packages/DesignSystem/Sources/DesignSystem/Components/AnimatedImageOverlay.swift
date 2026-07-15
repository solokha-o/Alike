import SwiftUI
import Lottie

public enum OverlayAnimationPlayback: Sendable, Equatable {
    case once
    case loop
}

public enum AnimatedImageAmbientMotion: Sendable, Equatable {
    case none
    case breathe
    case breatheInPlace
}

/// Composes static SwiftUI content with an optional transparent Lottie overlay.
///
/// The static content remains the source of truth. The overlay never handles
/// interaction, is omitted for Reduce Motion, and does not affect layout.
public struct AnimatedImageOverlay<StaticContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let animationURL: URL?
    private let aspectRatio: CGFloat
    private let maximumWidth: CGFloat?
    private let playback: OverlayAnimationPlayback
    private let ambientMotion: AnimatedImageAmbientMotion
    private let staticContent: StaticContent

    public init(
        animationURL: URL?,
        aspectRatio: CGFloat,
        maximumWidth: CGFloat? = nil,
        playback: OverlayAnimationPlayback = .once,
        ambientMotion: AnimatedImageAmbientMotion = .none,
        @ViewBuilder staticContent: () -> StaticContent
    ) {
        self.animationURL = animationURL
        self.aspectRatio = aspectRatio
        self.maximumWidth = maximumWidth
        self.playback = playback
        self.ambientMotion = ambientMotion
        self.staticContent = staticContent()
    }

    @ViewBuilder
    public var body: some View {
        if reduceMotion {
            composite
        } else {
            switch ambientMotion {
            case .none:
                composite
            case .breathe:
                composite
                    .phaseAnimator([false, true]) { content, isLifted in
                        content
                            .scaleEffect(isLifted ? 1.02 : 0.995)
                            .offset(
                                x: isLifted ? 2 : -2,
                                y: isLifted ? -6 : 2
                            )
                            .rotationEffect(.degrees(isLifted ? 0.7 : -0.5))
                    } animation: { _ in
                        .easeInOut(duration: 2.4)
                    }
            case .breatheInPlace:
                composite
                    .phaseAnimator([false, true]) { content, isExpanded in
                        content
                            .scaleEffect(isExpanded ? 1.012 : 0.998)
                    } animation: { _ in
                        .easeInOut(duration: 2.4)
                    }
            }
        }
    }

    private var composite: some View {
        ZStack {
            staticContent

            if !reduceMotion,
               let animationURL,
               let animation = LottieAnimation.filepath(animationURL.path) {
                LottieView(animation: animation)
                    .playing(.fromProgress(0, toProgress: 1, loopMode: loopMode))
                    .configure { animationView in
                        animationView.contentMode = .scaleAspectFit
                        animationView.shouldRasterizeWhenIdle = playback == .once
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxWidth: maximumWidth)
    }

    private var loopMode: LottieLoopMode {
        switch playback {
        case .once:
            .playOnce
        case .loop:
            .loop
        }
    }
}
