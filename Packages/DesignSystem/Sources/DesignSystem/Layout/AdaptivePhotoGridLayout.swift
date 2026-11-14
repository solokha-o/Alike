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
    }

    /// The regular-width policy for a container of `width` points: as many
    /// columns as keep each tile between ``TileWidth/minimum`` and
    /// ``TileWidth/maximum``, defaulting to about ``TileWidth/preferred``.
    ///
    /// Falls back to ``regular`` when the width is unknown or too small to hold
    /// 2 minimum tiles.
    public static func regular(containerWidth width: CGFloat?) -> AdaptivePhotoGridLayoutPolicy {
        guard let width, width.isFinite, width >= TileWidth.minimum * 2 else { return .regular }
        let most = max(2, Int((width / TileWidth.minimum).rounded(.down)))
        let fewest = min(most, max(2, Int((width / TileWidth.maximum).rounded(.up))))
        let preferred = Int((width / TileWidth.preferred).rounded())
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
