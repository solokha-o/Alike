import Core
import DesignSystem
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ALICleanupSuccessResultPresentation: Equatable {
    let staticImageURL: URL
    let animationURL: URL?
    let playback: OverlayAnimationPlayback
    let ambientMotion: AnimatedImageAmbientMotion
    let authorizedCueID: ALIReactionCueID?

    static func resolve(
        recordID: UUID,
        cue: ALIReactionCue?,
        displayScale: CGFloat,
        isVisible: Bool,
        scenePhase: ScenePhase
    ) -> Self {
        let matchingCueID = matchingCueID(recordID: recordID, cue: cue)
        let canPlay = matchingCueID != nil && isVisible && scenePhase == .active

        return Self(
            staticImageURL: ALIAssets.cleanupSuccessURL(for: imageScale(for: displayScale)),
            animationURL: canPlay ? ALIAssets.cleanupSuccessOverlayURL : nil,
            playback: .once,
            ambientMotion: .none,
            authorizedCueID: matchingCueID
        )
    }

    private static func matchingCueID(
        recordID: UUID,
        cue: ALIReactionCue?
    ) -> ALIReactionCueID? {
        guard
            let cue,
            cue.id == ALIReactionCueID(eventID: .cleanup(recordID), kind: .cleanupSuccess),
            case .cleanupSuccess = cue.state
        else { return nil }

        return cue.id
    }

    private static func imageScale(for displayScale: CGFloat) -> ALIAssets.CleanupSuccessScale {
        switch displayScale {
        case ..<1.5: .oneX
        case ..<2.5: .twoX
        default: .threeX
        }
    }
}

struct ALICleanupSuccessResultView: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    let record: CleanupCompletionRecord
    let cue: ALIReactionCue?
    let onConsumeCue: (ALIReactionCueID) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            header

            if usesHorizontalLayout {
                HStack(alignment: .center, spacing: Spacing.large) {
                    resultDetails
                    artwork
                }
            } else {
                VStack(spacing: Spacing.medium) {
                    resultDetails
                    artwork
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
        .subtleShadow()
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            consumeAuthorizedCue()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            consumeAuthorizedCue()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Text(appLocalized("Cleanup complete"))
                .font(.appTitle2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.headline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text(appLocalized("Dismiss")))
        }
    }

    private var resultDetails: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            metricLayout {
                metric(
                    title: appLocalized("photos moved"),
                    value: "\(record.deletedCount)",
                    detail: appLocalized("Recently Deleted")
                )

                metric(
                    title: appLocalized("Estimated Reclaimable"),
                    value: savingsText,
                    detail: appLocalized("Storage")
                )
            }

            Text(appLocalized("Your cleanup results are up to date."))
                .font(.appBody)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricLayout<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.small))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.small))
        return layout { content() }
    }

    private func metric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(title)
                .font(.appSubheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.small)
        .background(
            Color.statusReviewed.opacity(ColorOpacity.statusBackground),
            in: RoundedRectangle(cornerRadius: CornerRadius.small)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(value), \(detail)"))
    }

    private var artwork: some View {
        AnimatedImageOverlay(
            animationURL: presentation.animationURL,
            aspectRatio: 1,
            maximumWidth: artworkSize,
            playback: presentation.playback,
            ambientMotion: presentation.ambientMotion
        ) {
            staticArtwork
        }
        .id(presentation.authorizedCueID)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(appLocalized("ALI celebrates your completed cleanup")))
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var staticArtwork: some View {
#if canImport(UIKit)
        if let image = UIImage(contentsOfFile: presentation.staticImageURL.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            fallbackArtwork
        }
#elseif canImport(AppKit)
        if let image = NSImage(contentsOf: presentation.staticImageURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            fallbackArtwork
        }
#endif
    }

    private var fallbackArtwork: some View {
        Image(systemName: "checkmark.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Color.statusReviewed)
            .padding(artworkSize * 0.22)
    }

    private var presentation: ALICleanupSuccessResultPresentation {
        .resolve(
            recordID: record.id,
            cue: cue,
            displayScale: displayScale,
            isVisible: isVisible,
            scenePhase: scenePhase
        )
    }

    private var savingsText: String {
        ByteCountFormatter.string(
            fromByteCount: record.estimatedSavingsBytes,
            countStyle: .file
        )
    }

    private var usesHorizontalLayout: Bool {
        horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
    }

    private var artworkSize: CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 104 }
        return usesHorizontalLayout ? 152 : 120
    }

    private func consumeAuthorizedCue() {
        guard let cueID = presentation.authorizedCueID else { return }
        onConsumeCue(cueID)
    }
}
