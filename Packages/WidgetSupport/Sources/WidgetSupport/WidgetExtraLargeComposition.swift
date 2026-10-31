import Foundation

/// One of the largest groups, drawn under the «Similar photos» row: «≈420 MB» beside
/// «14 photos».
public struct WidgetClusterRow: Equatable, Sendable {
    public let bytes: String
    public let photos: String

    public init(bytes: String, photos: String) {
        self.bytes = bytes
        self.photos = photos
    }
}

/// The reclaimable estimate as a share of the whole library: the bar's fill and the
/// sentence under it.
public struct WidgetLibraryShare: Equatable, Sendable {
    /// `0...1`, never `nil` here: a share that is not known is no `WidgetLibraryShare`.
    public let fraction: Double
    /// «7% of your 26 GB of photos». Photos, not the library: the total is
    /// `PhotoAnalysisServiceImpl`'s sum over image assets, videos excluded.
    public let text: String
    /// `false` while a review is open: its progress bar is already under the headline,
    /// and a second bar right below it reads as a second progress figure.
    public let drawsBar: Bool

    public init(fraction: Double, text: String, drawsBar: Bool = true) {
        self.fraction = fraction
        self.text = text
        self.drawsBar = drawsBar
    }
}

/// Everything the extra-large portrait layout (iOS 27) needs, already decided.
///
/// Three zones on one widget: the status — the medium composition, so the two sizes
/// cannot disagree about a state — then what that figure is a share of, then the same
/// three category rows as the library widget, each its own `Link`. The largest groups
/// sit under the «Similar photos» row they belong to.
///
/// A sibling of `WidgetComposition` instead of new fields on it, and no new
/// `WidgetLayoutFamily` case: both are shipped, and the extension's switch over the
/// family keeps working untouched.
public struct WidgetExtraLargeComposition: Equatable, Sendable {
    public let base: WidgetComposition
    /// `nil` when either the estimate or the library size is unknown, or the state has
    /// no figure — never a bar drawn at zero.
    public let share: WidgetLibraryShare?
    /// The library widget's three rows. Empty until a scan has counted something, and
    /// for the states that have nothing to list.
    public let categoryRows: [WidgetLibraryRow]
    /// At most `WidgetSnapshot.topClustersLimit`, largest first. Empty for a state
    /// without figures and for a payload that predates `topClusters` — never a row of
    /// zeros.
    public let clusterRows: [WidgetClusterRow]
    /// Read out for the status zone. The category rows are `Link`s and carry their own.
    public let accessibilityLabel: String

    public init(
        base: WidgetComposition,
        share: WidgetLibraryShare?,
        categoryRows: [WidgetLibraryRow],
        clusterRows: [WidgetClusterRow],
        accessibilityLabel: String
    ) {
        self.base = base
        self.share = share
        self.categoryRows = categoryRows
        self.clusterRows = clusterRows
        self.accessibilityLabel = accessibilityLabel
    }
}

public extension WidgetPresentation {
    /// Resolves one display state and the snapshot behind it into the extra-large
    /// portrait widget.
    ///
    /// Takes the snapshot as well as the state for the same reason
    /// `libraryComposition(for:now:)` does: the category counts, the premium flag and
    /// the group sizes are not in `WidgetDisplayState`, and that enum is shipped.
    ///
    /// The share bar and the group rows appear only for the states that show a figure.
    /// The category rows appear for every state that has been scanned, «All caught up»
    /// included — they say what is in the library, which stays true when there is
    /// nothing left to review.
    static func extraLargeComposition(
        for state: WidgetDisplayState,
        snapshot: WidgetSnapshot?
    ) -> WidgetExtraLargeComposition {
        let base = composition(for: state, family: .medium)

        let figureBytes: Int64?
        let showsFigures: Bool
        let scanned: Bool
        switch state {
        case let .hasSuggestions(bytes, _, _, _), let .libraryChanged(bytes, _):
            (figureBytes, showsFigures, scanned) = (bytes, true, true)
        case .resumeReview:
            // The headline is the review's progress, but the estimate behind it is
            // still the snapshot's, and so is what it is a share of.
            (figureBytes, showsFigures, scanned) = (snapshot?.estimatedSavingsBytes, true, true)
        case .allCaughtUp:
            (figureBytes, showsFigures, scanned) = (nil, false, true)
        case .unavailable, .noAccess, .neverScanned:
            (figureBytes, showsFigures, scanned) = (nil, false, false)
        }

        let share = libraryShare(of: figureBytes, in: snapshot?.libraryTotalBytes, drawsBar: base.progress == nil)
        let categoryRows = scanned ? (snapshot.map(libraryRows(for:)) ?? []) : []
        let clusterRows = showsFigures
            ? WidgetClusterSummary.top(snapshot?.topClusters ?? []).map {
                WidgetClusterRow(
                    bytes: WidgetFormatting.approximateByteCount($0.reclaimableBytes),
                    photos: WidgetL10n.Library.photos($0.photoCount)
                )
            }
            : []

        let label = [base.headline, base.caption, share?.text, base.footnote]
            .compactMap { $0 }
            .joined(separator: ", ")

        return WidgetExtraLargeComposition(
            base: base,
            share: share,
            categoryRows: categoryRows,
            clusterRows: clusterRows,
            accessibilityLabel: label
        )
    }
}

private extension WidgetPresentation {
    /// «7% of your 26 GB of photos». A share that rounds to nothing still reads «1%»: the
    /// line is shown because there is something to reclaim, and «0%» would deny it.
    static func libraryShare(of bytes: Int64?, in total: Int64?, drawsBar: Bool) -> WidgetLibraryShare? {
        guard let bytes, bytes > 0, let total, let fraction = share(of: bytes, in: total) else { return nil }
        let shown = max(fraction, 0.01)
        let percent = WidgetFormatting.percent(shown)
        return WidgetLibraryShare(
            fraction: fraction,
            text: WidgetL10n.Status.shareOfLibrary(percent, WidgetFormatting.byteCount(total)),
            drawsBar: drawsBar
        )
    }
}
