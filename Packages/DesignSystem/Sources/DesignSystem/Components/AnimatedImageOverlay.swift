import SwiftUI
import Lottie

public enum OverlayAnimationPlayback: Sendable, Equatable {
    case once
    case loop
}

public enum AnimatedImageAmbientMotion: Sendable, Equatable {
    case none
    case breathe
}

/// Composes static SwiftUI content with an optional transparent Lottie overlay.
///
/// The static content remains the source of truth. The overlay never handles
/// interaction, is omitted for Reduce Motion, and does not affect layout.
public struct AnimatedImageOverlay<StaticContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ambientPhaseIsLifted = false

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

    public var body: some View {
        composite
            // Ambient motion is a `repeatForever` animation, and it is installed
            // in the same update that makes the content visible: the overlay is
            // only resolved once the view appears, and the static artwork can
            // still be decoding. Without this, that content layout change
            // inherits the looping animation and oscillates between zero and
            // full size forever instead of settling. Only the transforms below
            // may animate.
            .transaction { $0.animation = nil }
            .scaleEffect(
                animatesAmbientMotion
                    ? (ambientPhaseIsLifted ? 1.02 : 0.995)
                    : 1
            )
            .offset(
                x: animatesAmbientMotion ? (ambientPhaseIsLifted ? 2 : -2) : 0,
                y: animatesAmbientMotion ? (ambientPhaseIsLifted ? -6 : 2) : 0
            )
            .rotationEffect(
                .degrees(
                    animatesAmbientMotion
                        ? (ambientPhaseIsLifted ? 0.7 : -0.5)
                        : 0
                )
            )
            .animation(ambientAnimation, value: ambientPhaseIsLifted)
            .onAppear { ambientPhaseIsLifted = animatesAmbientMotion }
            .onChange(of: animatesAmbientMotion) { _, shouldAnimate in
                ambientPhaseIsLifted = shouldAnimate
            }
    }

    private var composite: some View {
        ZStack {
            staticContent

            if Self.shouldRenderAnimation(
                animationURL: animationURL,
                reduceMotion: reduceMotion
            ), let animationURL,
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
        // The box is sized by the proposal and the aspect ratio alone, never by
        // its children. The overlay is inserted only once the view becomes
        // visible; letting that insertion resize the box hands a layout change
        // to the ambient `repeatForever` animation, which then slides the
        // artwork back and forth forever.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var animatesAmbientMotion: Bool {
        Self.shouldAnimateAmbientMotion(
            ambientMotion: ambientMotion,
            reduceMotion: reduceMotion
        )
    }

    private var ambientAnimation: Animation? {
        guard animatesAmbientMotion else { return nil }
        return .easeInOut(duration: 2.4).repeatForever(autoreverses: true)
    }

    static func shouldAnimateAmbientMotion(
        ambientMotion: AnimatedImageAmbientMotion,
        reduceMotion: Bool
    ) -> Bool {
        ambientMotion == .breathe && !reduceMotion
    }

    static func shouldRenderAnimation(
        animationURL: URL?,
        reduceMotion: Bool
    ) -> Bool {
        animationURL != nil && !reduceMotion
    }
}
