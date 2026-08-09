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

/// Full period of the ambient breathe, matching the 2.4s auto-reversing
/// animation this replaced.
let ambientMotionCycleDuration: TimeInterval = 4.8

/// Eased 0...1 loop over ``ambientMotionCycleDuration``, derived from wall-clock
/// time so the motion never restarts and no SwiftUI animation is involved.
func ambientMotionPhase(at date: Date) -> Double {
    let elapsed = date.timeIntervalSinceReferenceDate
        .truncatingRemainder(dividingBy: ambientMotionCycleDuration)
    return (1 - cos(2 * .pi * elapsed / ambientMotionCycleDuration)) / 2
}

/// Transform values for one point in the ambient cycle. A `nil` phase means
/// ambient motion is off and every value is the identity.
struct AmbientMotionValues {
    let scale: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let rotationDegrees: Double

    init(phase: Double?) {
        guard let phase else {
            scale = 1
            offsetX = 0
            offsetY = 0
            rotationDegrees = 0
            return
        }
        let progress = CGFloat(min(max(phase, 0), 1))
        scale = 0.995 + (1.02 - 0.995) * progress
        offsetX = -2 + 4 * progress
        offsetY = 2 - 8 * progress
        rotationDegrees = -0.5 + 1.2 * Double(progress)
    }
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

    /// Ambient motion is driven from wall-clock time rather than a
    /// `repeatForever` animation on purpose.
    ///
    /// A looping animation is attached to the view, not to the three transforms
    /// it was written for, so any layout change that lands while the loop is
    /// installed — the Lottie overlay appearing once the view becomes visible,
    /// artwork resolving, an ancestor re-laying-out — is adopted by the loop and
    /// repeated forever. That is what made the hero collapse to a fraction of
    /// its size and slide across the card on a 4.8s cycle. Deriving the phase
    /// from the timeline means no animation exists for layout to inherit, and
    /// the motion also never restarts when unrelated state changes.
    public var body: some View {
        TimelineView(.animation(paused: !animatesAmbientMotion)) { context in
            let motion = AmbientMotionValues(
                phase: animatesAmbientMotion ? ambientMotionPhase(at: context.date) : nil
            )
            composite
                .scaleEffect(motion.scale)
                .offset(x: motion.offsetX, y: motion.offsetY)
                .rotationEffect(.degrees(motion.rotationDegrees))
        }
    }

    private var composite: some View {
        // The geometry comes from the static content alone. The overlay is an
        // `.overlay` rather than a `ZStack` sibling so it cannot participate in
        // sizing, keeping the promise in this type's documentation that the
        // overlay never affects layout.
        staticContent
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: maximumWidth)
            .overlay { animationOverlay }
    }

    @ViewBuilder
    private var animationOverlay: some View {
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
