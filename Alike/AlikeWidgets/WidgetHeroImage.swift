//
//  WidgetHeroImage.swift
//  AlikeWidgets
//

import SwiftUI
import WidgetKit
import WidgetSupport

/// A hero scene, decoded at the size it is drawn.
///
/// Purely decorative: every composition that names a hero also says the same thing in
/// words, so the image is hidden from accessibility rather than given a label VoiceOver
/// would read twice.
struct WidgetHeroImage: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.widgetRenderingMode) private var renderingMode

    let scene: WidgetHeroScene
    /// The square the scene is drawn into. The decode is sized to it, so it is also the
    /// most pixels the extension will ever hold for one hero.
    let size: CGFloat

    var body: some View {
        // The tinted and vibrant home screens render a widget as a single-colour
        // stencil. A flat silhouette of an illustration is not the illustration, so the
        // hero steps aside and the numbers get the space instead.
        if renderingMode == .fullColor, let image {
            Image(decorative: image, scale: displayScale > 0 ? displayScale : 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    /// `nil` for a missing or unreadable file. A widget without its illustration is a
    /// widget; a widget that traps on a missing resource is a blank rectangle on
    /// someone's home screen.
    private var image: CGImage? {
        WidgetHeroImageLoader.cgImage(
            at: WidgetHeroAssets.url(for: scene, scale: WidgetHeroScale(displayScale: displayScale)),
            maxPixelSize: WidgetHeroImageLoader.maxPixelSize(pointSize: size, displayScale: displayScale)
        )
    }
}
