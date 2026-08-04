import Core
import SwiftUI

@MainActor
private final class AlikePlatformImageCache {
    static let shared = AlikePlatformImageCache()

#if canImport(UIKit)
    private let images = NSCache<NSURL, UIImage>()

    func image(at url: URL) -> UIImage? {
        if let cached = images.object(forKey: url as NSURL) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }
#elseif canImport(AppKit)
    private let images = NSCache<NSURL, NSImage>()

    func image(at url: URL) -> NSImage? {
        if let cached = images.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }
#endif
}

public struct AlikeReactionPresentation: Equatable, Sendable {
    public let kind: AlikeReactionKind
    public let staticImageURL: URL?
    public let fallbackStaticImageURL: URL?
    public let animationURL: URL?
    public let fallbackSystemImageName: String
    public let playback: OverlayAnimationPlayback
    public let ambientMotion: AnimatedImageAmbientMotion
    public let accessibilityLabel: String

    public static func resolve(
        cue: AlikeReactionCue,
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
                staticImageURL: AlikeAssets.optionalScannerIdleURL(for: idleState, scale: imageScale),
                fallbackStaticImageURL: scannerReadyURL(for: imageScale),
                animationURL: canPlay && !usesCalmStaticPresentation
                    ? AlikeAssets.scannerIdleOverlayURL(for: idleState)
                    : nil,
                fallbackSystemImageName: "photo.stack",
                playback: .loop,
                ambientMotion: canPlay && !usesCalmStaticPresentation ? .breathe : .none,
                accessibilityLabel: idleAccessibilityLabel(for: context)
            )

        case .scanning:
            return Self(
                kind: .scanning,
                staticImageURL: AlikeAssets.optionalScannerSearchingURL(
                    for: scannerSearchingScale(for: displayScale)
                ),
                fallbackStaticImageURL: scannerReadyURL(for: imageScale),
                animationURL: canPlay ? AlikeAssets.scannerSearchingOverlayURL : nil,
                fallbackSystemImageName: "camera.viewfinder",
                playback: .loop,
                ambientMotion: canPlay ? .breathe : .none,
                accessibilityLabel: appLocalized("Alike searching for similar photos")
            )

        case .resultsFound:
            return nativeFallback(
                kind: .resultsFound,
                symbol: "sparkles",
                label: appLocalized("Alike found cleanup opportunities")
            )

        case .noResults:
            return Self(
                kind: .noResults,
                staticImageURL: AlikeAssets.optionalScannerIdleURL(
                    for: .allCaughtUp,
                    scale: imageScale
                ),
                fallbackStaticImageURL: scannerReadyURL(for: imageScale),
                animationURL: nil,
                fallbackSystemImageName: "checkmark.circle.fill",
                playback: .once,
                ambientMotion: .none,
                accessibilityLabel: appLocalized("Alike says your photo library is all caught up")
            )

        case .cleanupReady:
            return nativeFallback(
                kind: .cleanupReady,
                symbol: "checklist",
                label: appLocalized("Alike is ready for cleanup")
            )

        case .cleanupSuccess:
            return Self(
                kind: .cleanupSuccess,
                staticImageURL: AlikeAssets.cleanupSuccessURL(
                    for: cleanupSuccessScale(for: displayScale)
                ),
                fallbackStaticImageURL: nil,
                animationURL: canPlay ? AlikeAssets.cleanupSuccessOverlayURL : nil,
                fallbackSystemImageName: "party.popper.fill",
                playback: .once,
                ambientMotion: .none,
                accessibilityLabel: appLocalized("Alike celebrates your completed cleanup")
            )

        case .permissionIssue:
            return nativeFallback(
                kind: .permissionIssue,
                symbol: "lock.trianglebadge.exclamationmark",
                label: appLocalized("Alike needs photo library permission to continue")
            )

        case .recoverableError:
            return Self(
                kind: .recoverableError,
                staticImageURL: AlikeAssets.optionalScannerIssueURL(
                    for: scannerIssueScale(for: displayScale)
                ),
                fallbackStaticImageURL: scannerReadyURL(for: imageScale),
                animationURL: nil,
                fallbackSystemImageName: "exclamationmark.triangle",
                playback: .once,
                ambientMotion: .none,
                accessibilityLabel: appLocalized("Alike ran into a problem with the scan")
            )
        }
    }

    private static func nativeFallback(
        kind: AlikeReactionKind,
        symbol: String,
        label: String
    ) -> Self {
        Self(
            kind: kind,
            staticImageURL: nil,
            fallbackStaticImageURL: nil,
            animationURL: nil,
            fallbackSystemImageName: symbol,
            playback: kind == .scanning ? .loop : .once,
            ambientMotion: .none,
            accessibilityLabel: label
        )
    }

    private static func scannerIdleState(for context: AlikeIdleContext) -> AlikeAssets.ScannerIdleState {
        switch context {
        case .ready: .ready
        case .hasReviews: .hasReviews
        case .allCaughtUp: .allCaughtUp
        case .libraryChanged: .libraryChanged
        }
    }

    private static func imageScale(for displayScale: CGFloat) -> AlikeAssets.ScannerIdleScale {
        switch displayScale {
        case ..<1.5: .oneX
        case ..<2.5: .twoX
        default: .threeX
        }
    }

    private static func scannerSearchingScale(
        for displayScale: CGFloat
    ) -> AlikeAssets.ScannerSearchingScale {
        switch displayScale {
        case ..<1.5: .oneX
        case ..<2.5: .twoX
        default: .threeX
        }
    }

    private static func scannerIssueScale(
        for displayScale: CGFloat
    ) -> AlikeAssets.ScannerIssueScale {
        switch displayScale {
        case ..<1.5: .oneX
        case ..<2.5: .twoX
        default: .threeX
        }
    }

    private static func scannerReadyURL(
        for scale: AlikeAssets.ScannerIdleScale
    ) -> URL? {
        AlikeAssets.optionalScannerIdleURL(for: .ready, scale: scale)
    }

    private static func idleAccessibilityLabel(for context: AlikeIdleContext) -> String {
        switch context {
        case .ready:
            appLocalized("Alike is ready to help organize your photo library")
        case .hasReviews:
            appLocalized("Alike has cleanup opportunities ready for review")
        case .allCaughtUp:
            appLocalized("Alike says your photo library is all caught up")
        case .libraryChanged:
            appLocalized("Alike noticed new photos in your library")
        }
    }

    private static func cleanupSuccessScale(
        for displayScale: CGFloat
    ) -> AlikeAssets.CleanupSuccessScale {
        switch displayScale {
        case ..<1.5: .oneX
        case ..<2.5: .twoX
        default: .threeX
        }
    }
}

/// Passive, non-interactive rendering of an already-resolved Alike reaction cue.
public struct AlikeReactionView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    private let cue: AlikeReactionCue
    private let maximumWidth: CGFloat

    public init(cue: AlikeReactionCue, maximumWidth: CGFloat = 72) {
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
        if let image = platformImage(at: presentation.staticImageURL) {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if let image = platformImage(at: presentation.fallbackStaticImageURL) {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            fallbackImage
        }
    }

    private func platformImage(at url: URL?) -> Image? {
        guard let url else { return nil }
#if canImport(UIKit)
        guard let image = AlikePlatformImageCache.shared.image(at: url) else { return nil }
        return Image(uiImage: image)
#elseif canImport(AppKit)
        guard let image = AlikePlatformImageCache.shared.image(at: url) else { return nil }
        return Image(nsImage: image)
#endif
    }

    private var fallbackImage: some View {
        Image(systemName: presentation.fallbackSystemImageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Color.accent)
            .padding(maximumWidth * 0.2)
    }

    private var presentation: AlikeReactionPresentation {
        .resolve(
            cue: cue,
            displayScale: displayScale,
            isVisible: isVisible,
            scenePhase: scenePhase
        )
    }
}
