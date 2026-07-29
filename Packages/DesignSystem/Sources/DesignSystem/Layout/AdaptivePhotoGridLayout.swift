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
}

public struct PhotoThumbnailAspectRatioLayout: Layout {
    private let aspectRatio: CGFloat

    public init(aspectRatio: CGFloat) {
        self.aspectRatio = aspectRatio
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
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
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
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
