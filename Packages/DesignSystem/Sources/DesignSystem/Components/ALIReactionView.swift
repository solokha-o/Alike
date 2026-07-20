import Core
import SwiftUI

public struct ALIReactionPresentation: Equatable, Sendable {
    public let kind: ALIReactionKind
    public let staticImageURL: URL?
    public let animationURL: URL?
    public let fallbackSystemImageName: String
    public let playback: OverlayAnimationPlayback
    public let ambientMotion: AnimatedImageAmbientMotion
    public let accessibilityLabel: String

    public static func resolve(
        cue: ALIReactionCue,
        displayScale: CGFloat,
        isVisible: Bool,
        scenePhase: ScenePhase
    ) -> Self {
        let canPlay = isVisible && scenePhase == .active
        let imageScale = imageScale(for: displayScale)

        switch cue.state {
        case .idle(let context):
            let idleState = scannerIdleState(for: context)
            let usesCalmStaticPresentation = context == .allCaughtUp
            return Self(
                kind: .idle,
                staticImageURL: ALIAssets.optionalScannerIdleURL(for: idleState, scale: imageScale),
                animationURL: canPlay && !usesCalmStaticPresentation
                    ? ALIAssets.scannerIdleOverlayURL(for: idleState)
                    : nil,
                fallbackSystemImageName: "photo.stack",
                playback: .loop,
                ambientMotion: canPlay && !usesCalmStaticPresentation ? .breathe : .none,
                accessibilityLabel: appLocalized("ALI is ready to help organize your photo library")
            )

        case .scanning:
            return Self(
                kind: .scanning,
                staticImageURL: ALIAssets.optionalScannerSearchingURL(
                    for: scannerSearchingScale(for: displayScale)
                ),
                animationURL: canPlay ? ALIAssets.scannerSearchingOverlayURL : nil,
                fallbackSystemImageName: "camera.viewfinder",
                playback: .loop,
                ambientMotion: canPlay ? .breathe : .none,
                accessibilityLabel: appLocalized("ALI searching for similar photos")
            )

        case .resultsFound:
            return nativeFallback(
                kind: .resultsFound,
                symbol: "sparkles",
                label: appLocalized("ALI found cleanup opportunities")
            )

        case .noResults:
            return Self(
                kind: .noResults,
                staticImageURL: ALIAssets.optionalScannerIdleURL(
                    for: .allCaughtUp,
                    scale: imageScale
                ),
                animationURL: nil,
                fallbackSystemImageName: "checkmark.circle.fill",
                playback: .once,
                ambientMotion: .none,
                accessibilityLabel: appLocalized("ALI says your photo library is all caught up")
            )

        case .cleanupReady:
            return nativeFallback(
                kind: .cleanupReady,
                symbol: "checklist",
                label: appLocalized("ALI is ready for cleanup")
            )

        case .cleanupSuccess:
            return Self(
                kind: .cleanupSuccess,
                staticImageURL: ALIAssets.cleanupSuccessURL(
                    for: cleanupSuccessScale(for: displayScale)
                ),
                animationURL: canPlay ? ALIAssets.cleanupSuccessOverlayURL : nil,
                fallbackSystemImageName: "party.popper.fill",
                playback: .once,
                ambientMotion: .none,
                accessibilityLabel: appLocalized("ALI celebrates your completed cleanup")
            )

        case .permissionIssue:
            return nativeFallback(
                kind: .permissionIssue,
                symbol: "lock.trianglebadge.exclamationmark",
                label: appLocalized("ALI needs photo library permission to continue")
            )

        case .recoverableError:
            return nativeFallback(
                kind: .recoverableError,
                symbol: "exclamationmark.triangle",
                label: appLocalized("ALI could not complete the current operation")
            )
        }
    }

    private static func nativeFallback(
        kind: ALIReactionKind,
        symbol: String,
        label: String
    ) -> Self {
        Self(
            kind: kind,
            staticImageURL: nil,
            animationURL: nil,
            fallbackSystemImageName: symbol,
            playback: kind == .scanning ? .loop : .once,
            ambientMotion: .none,
            accessibilityLabel: label
        )
    }

    private static func scannerIdleState(for context: ALIIdleContext) -> ALIAssets.ScannerIdleState {
        switch context {
        case .ready: .ready
        case .hasReviews: .hasReviews
        case .allCaughtUp: .allCaughtUp
        case .libraryChanged: .libraryChanged
        }
    }

    private static func imageScale(for displayScale: CGFloat) -> ALIAssets.ScannerIdleScale {
        switch displayScale {
        case ..<1.5: .oneX
        case ..<2.5: .twoX
        default: .threeX
        }
    }

    private static func scannerSearchingScale(
        for displayScale: CGFloat
    ) -> ALIAssets.ScannerSearchingScale {
        switch displayScale {
        case ..<1.5: .oneX
        case ..<2.5: .twoX
        default: .threeX
        }
    }

    private static func cleanupSuccessScale(
        for displayScale: CGFloat
    ) -> ALIAssets.CleanupSuccessScale {
        switch displayScale {
        case ..<1.5: .oneX
        case ..<2.5: .twoX
        default: .threeX
        }
    }
}

/// Passive, non-interactive rendering of an already-resolved ALI reaction cue.
public struct ALIReactionView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    private let cue: ALIReactionCue
    private let maximumWidth: CGFloat

    public init(cue: ALIReactionCue, maximumWidth: CGFloat = 72) {
        self.cue = cue
        self.maximumWidth = maximumWidth
    }

    public var body: some View {
        AnimatedImageOverlay(
            animationURL: presentation.animationURL,
            aspectRatio: 1,
            maximumWidth: maximumWidth,
            playback: presentation.playback,
            ambientMotion: presentation.ambientMotion
        ) {
            staticContent
        }
        .id(cue.id)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(presentation.accessibilityLabel))
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    @ViewBuilder
    private var staticContent: some View {
        if let url = presentation.staticImageURL {
#if canImport(UIKit)
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                fallbackImage
            }
#elseif canImport(AppKit)
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                fallbackImage
            }
#endif
        } else {
            fallbackImage
        }
    }

    private var fallbackImage: some View {
        Image(systemName: presentation.fallbackSystemImageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Color.accent)
            .padding(maximumWidth * 0.2)
    }

    private var presentation: ALIReactionPresentation {
        .resolve(
            cue: cue,
            displayScale: displayScale,
            isVisible: isVisible,
            scenePhase: scenePhase
        )
    }
}
