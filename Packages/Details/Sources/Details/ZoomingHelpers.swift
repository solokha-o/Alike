import CoreGraphics

enum ZoomingHelpers {
    static func clampedOffset(
        _ proposed: CGSize,
        in size: CGSize,
        scale: CGFloat
    ) -> CGSize {
        let maxX = (size.width * (scale - 1)) / 2
        let maxY = (size.height * (scale - 1)) / 2
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}
