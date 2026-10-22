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
        if let image {
            if renderingMode == .fullColor {
                framed(heroImage(image))
            } else if renderingMode == .accented, #available(iOS 18.0, *) {
                // The tinted and clear Home Screens render `.accented`. From iOS 18 an
                // image can opt out of the stencil, so the illustration keeps its own
                // colours there while the text and glyphs around it still take the tint.
                framed(heroImage(image).widgetAccentedRenderingMode(.fullColor))
            }
            // Otherwise — the vibrant Lock Screen, or `.accented` on iOS 17 — the widget
            // is a single-colour stencil. A flat silhouette of an illustration is not
            // the illustration, so the hero steps aside and the numbers get the space.
        }
    }

    private func heroImage(_ image: CGImage) -> Image {
        Image(decorative: image, scale: displayScale > 0 ? displayScale : 1)
            .resizable()
    }

    private func framed(_ content: some View) -> some View {
        content
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
