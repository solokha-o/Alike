import SwiftUI
import Core
import DesignSystem

struct AlikeBestShotCelebrationPresentation: Equatable {
    let animationURL: URL?
    let playback: OverlayAnimationPlayback
    let ambientMotion: AnimatedImageAmbientMotion

    static func resolve(isVisible: Bool, scenePhase: ScenePhase) -> Self {
        let isMotionEnabled = isVisible && scenePhase == .active

        return Self(
            animationURL: isMotionEnabled ? AlikeAssets.bestShotOverlayURL : nil,
            // Product intent: the effect is a seamless loop bounded by the cue lifetime below.
            // Do not change this to `.once`; visibility and timed cue consumption stop playback.
            playback: .loop,
            ambientMotion: .none
        )
    }

    static func imageURL(for displayScale: CGFloat) -> URL {
        AlikeAssets.bestShotURL(for: imageScale(for: displayScale))
    }

    private static func imageScale(for displayScale: CGFloat) -> AlikeAssets.BestShotScale {
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

struct AlikeBestShotCelebrationView: View {
    private enum Constants {
        static let maximumWidth: CGFloat = 72
        static let playbackDuration: Duration = .seconds(4)
    }

    private struct PlaybackTaskID: Hashable {
        let cueID: AlikeReviewReactionCue.ID
        let canPlay: Bool
    }

    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    let cueID: AlikeReviewReactionCue.ID
    let onPlaybackFinished: () -> Void

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
        .id(cueID)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(appLocalized("Alike celebrating the Best Shot")))
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
        .task(id: playbackTaskID) {
            guard playbackTaskID.canPlay else { return }
            do {
                try await Task.sleep(for: Constants.playbackDuration)
            } catch {
                return
            }
            onPlaybackFinished()
        }
    }

    @ViewBuilder
    private var bestShotImage: some View {
        let imageURL = AlikeBestShotCelebrationPresentation.imageURL(for: displayScale)

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

    private var presentation: AlikeBestShotCelebrationPresentation {
        .resolve(isVisible: isVisible, scenePhase: scenePhase)
    }

    private var playbackTaskID: PlaybackTaskID {
        PlaybackTaskID(cueID: cueID, canPlay: isVisible && scenePhase == .active)
    }
}
