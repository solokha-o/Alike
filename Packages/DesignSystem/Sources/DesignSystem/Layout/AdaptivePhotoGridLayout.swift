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
        guard aspectRatio > 0 else { return .zero }

        if let width = proposal.width, width.isFinite {
            return CGSize(width: width, height: width / aspectRatio)
        }
        if let height = proposal.height, height.isFinite {
            return CGSize(width: height * aspectRatio, height: height)
        }

        let fallback = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: fallback.width, height: fallback.width / aspectRatio)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        for subview in subviews {
            subview.place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(bounds.size)
            )
        }
    }
}
