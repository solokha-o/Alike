import SwiftUI

public struct AdaptivePhotoGridLayoutPolicy: Equatable, Sendable {
    public let columnCounts: ClosedRange<Int>
    public let defaultColumnCount: Int

    public static let compact = AdaptivePhotoGridLayoutPolicy(
        columnCounts: 1...2,
        defaultColumnCount: 2
    )
    public static let regular = AdaptivePhotoGridLayoutPolicy(
        columnCounts: 2...5,
        defaultColumnCount: 4
    )

    public func clampedColumnCount(_ value: Int) -> Int {
        min(max(value, columnCounts.lowerBound), columnCounts.upperBound)
    }

    /// Tile widths, in points, that a regular-width grid keeps between.
    public enum TileWidth {
        /// Narrower tiles make the photos too small to judge.
        public static let minimum: CGFloat = 150
        /// Wider tiles waste the screen: a 13-inch iPad showed 1 row of 330 pt tiles.
        public static let maximum: CGFloat = 320
        /// The width the default column count aims for.
        public static let preferred: CGFloat = 200
        /// Side padding of a grid screen, both sides together (Cleanup: 16 + 16).
        public static let containerInset: CGFloat = 32
        /// The widest gap between 2 tiles in a grid screen (Cleanup: 12 pt).
        public static let gap: CGFloat = 12

        /// The tile width with `columns` columns in a container of `width` points.
        public static func tileWidth(columns: Int, containerWidth width: CGFloat) -> CGFloat {
            (width - containerInset - CGFloat(columns - 1) * gap) / CGFloat(columns)
        }
    }

    /// The regular-width policy for a container of `width` points: as many
    /// columns as keep each tile between ``TileWidth/minimum`` and
    /// ``TileWidth/maximum``, after the screen's padding and gaps, defaulting
    /// to about ``TileWidth/preferred``.
    ///
    /// Falls back to ``regular`` when the width is unknown or too small to hold
    /// 2 minimum tiles.
    public static func regular(containerWidth width: CGFloat?) -> AdaptivePhotoGridLayoutPolicy {
        guard let width, width.isFinite,
              TileWidth.tileWidth(columns: 2, containerWidth: width) >= TileWidth.minimum
        else { return .regular }
        // n tiles and n - 1 gaps fit in the width without the padding:
        // n * tile + (n - 1) * gap <= width - inset  <=>  n <= (width - inset + gap) / (tile + gap)
        let usable = width - TileWidth.containerInset + TileWidth.gap
        let most = max(2, Int((usable / (TileWidth.minimum + TileWidth.gap)).rounded(.down)))
        let fewest = min(most, max(2, Int((usable / (TileWidth.maximum + TileWidth.gap)).rounded(.up))))
        let preferred = Int((usable / (TileWidth.preferred + TileWidth.gap)).rounded())
        return AdaptivePhotoGridLayoutPolicy(
            columnCounts: fewest...most,
            defaultColumnCount: min(max(preferred, fewest), most)
        )
    }

#if os(iOS)
    public static func forHorizontalSizeClass(
        _ sizeClass: UserInterfaceSizeClass?
    ) -> AdaptivePhotoGridLayoutPolicy {
        sizeClass == .regular ? .regular : .compact
    }

    /// Compact width keeps ``compact``; regular width follows the container.
    public static func forHorizontalSizeClass(
        _ sizeClass: UserInterfaceSizeClass?,
        containerWidth: CGFloat?
    ) -> AdaptivePhotoGridLayoutPolicy {
        sizeClass == .regular ? .regular(containerWidth: containerWidth) : .compact
    }
#endif
}

public struct PhotoThumbnailAspectRatioLayout: Layout {
    private let aspectRatio: CGFloat

    public init(aspectRatio: CGFloat) {
        self.aspectRatio = aspectRatio
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        let fallback = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return PhotoThumbnailAspectRatioSizePolicy.size(
            proposedWidth: proposal.width,
            proposedHeight: proposal.height,
            fallback: fallback,
            aspectRatio: aspectRatio
        )
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        guard PhotoThumbnailAspectRatioSizePolicy.isRenderable(bounds.size) else { return }

        for subview in subviews {
            subview.place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(bounds.size)
            )
        }
    }
}

public enum PhotoThumbnailAspectRatioSizePolicy {
    public static func size(
        proposedWidth: CGFloat?,
        proposedHeight: CGFloat?,
        fallback: CGSize,
        aspectRatio: CGFloat
    ) -> CGSize {
        guard aspectRatio.isFinite, aspectRatio > 0 else { return .zero }

        if let proposedWidth, proposedWidth.isFinite, proposedWidth > 0 {
            return CGSize(width: proposedWidth, height: proposedWidth / aspectRatio)
        }
        if let proposedHeight, proposedHeight.isFinite, proposedHeight > 0 {
            return CGSize(width: proposedHeight * aspectRatio, height: proposedHeight)
        }
        if fallback.width.isFinite, fallback.width > 0 {
            return CGSize(width: fallback.width, height: fallback.width / aspectRatio)
        }
        return .zero
    }

    public static func isRenderable(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
