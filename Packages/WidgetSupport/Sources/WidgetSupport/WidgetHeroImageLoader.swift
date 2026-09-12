import CoreGraphics
import Foundation
import ImageIO

/// Decodes hero artwork at the size it will actually be drawn.
///
/// The scenes are 1254×1254 at @3x, which is right for a full-screen illustration and
/// wrong for a widget: `UIImage(contentsOfFile:)` would decode ~6.3 MB of bitmap to
/// paint a 60–90 pt mark, against an extension memory budget around 30 MB. ImageIO's
/// thumbnail path decodes straight to the requested bound instead, which costs roughly
/// a twentieth of that and produces the same picture at the size it is shown.
///
/// Loading lives here rather than in the extension target because the extension has no
/// test action; `WidgetHeroImageLoaderTests` exercises it in the package's own workspace.
public enum WidgetHeroImageLoader {
    /// The decoded scene, no larger than `maxPixelSize` on its longest edge.
    ///
    /// Returns `nil` for a missing file, a file that is not an image, and any size that
    /// is not a positive number of pixels — every one of those is a reason to render the
    /// composition without a hero, never a reason to trap.
    public static func cgImage(at url: URL?, maxPixelSize: Int) -> CGImage? {
        guard let url, maxPixelSize > 0 else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Without this the source's own embedded thumbnail wins when it has one, and
            // that thumbnail is whatever the exporter felt like writing.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The pixel bound for drawing a scene at `pointSize` on a screen of `displayScale`.
    public static func maxPixelSize(pointSize: CGFloat, displayScale: CGFloat) -> Int {
        // A widget can be rendered before the environment carries a real scale; falling
        // back to 1 keeps the bound positive rather than collapsing it to zero.
        let scale = displayScale > 0 ? displayScale : 1
        return max(1, Int((pointSize * scale).rounded(.up)))
    }
}
