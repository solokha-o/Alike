import CoreGraphics

/// Resolves the pixel size to request for a fullscreen, zoomable photo.
///
/// Requesting `PHImageManagerMaximumSize` decodes the asset at full resolution, which for modern
/// captures can exceed the memory PhotoKit is willing to hand back — the request then fails rather
/// than returning a downscaled image. A viewer only ever displays viewport pixels, so bounding the
/// request to the viewport scaled by the maximum zoom keeps quality identical while staying well
/// inside PhotoKit's budget.
public enum PhotoFullscreenImageSizePolicy {
    /// Upper bound on either dimension, chosen to stay comfortably under PhotoKit's decode limits.
    public static let maximumPixelDimension: CGFloat = 4_096

    /// Used when the viewport has not been laid out yet and would otherwise request a zero size.
    public static let fallbackPointDimension: CGFloat = 1_024

    public static func targetSize(
        viewportSize: CGSize,
        displayScale: CGFloat,
        maximumZoomScale: CGFloat
    ) -> CGSize {
        let resolvedScale = displayScale.isFinite && displayScale > 0 ? displayScale : 1
        let resolvedZoom = maximumZoomScale.isFinite && maximumZoomScale > 1 ? maximumZoomScale : 1
        let width = resolvedDimension(viewportSize.width)
        let height = resolvedDimension(viewportSize.height)

        return clamped(
            CGSize(
                width: width * resolvedScale * resolvedZoom,
                height: height * resolvedScale * resolvedZoom
            )
        )
    }

    private static func resolvedDimension(_ value: CGFloat) -> CGFloat {
        value.isFinite && value > 0 ? value : fallbackPointDimension
    }

    /// Rounds to whole pixels so repeated layout passes reuse the same `PhotoImageCache` key.
    private static func clamped(_ size: CGSize) -> CGSize {
        let longestSide = max(size.width, size.height)
        guard longestSide > maximumPixelDimension else {
            return CGSize(width: size.width.rounded(), height: size.height.rounded())
        }

        let reduction = maximumPixelDimension / longestSide
        return CGSize(
            width: (size.width * reduction).rounded(),
            height: (size.height * reduction).rounded()
        )
    }
}
