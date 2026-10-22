import Foundation

/// One group row of the extra-large widget: «≈420 MB» beside «14 photos».
public struct WidgetClusterRow: Equatable, Sendable {
    public let bytes: String
    public let photos: String

    public init(bytes: String, photos: String) {
        self.bytes = bytes
        self.photos = photos
    }
}

/// Everything the extra-large portrait layout (iOS 27) needs, already decided.
///
/// The medium composition plus the room the bigger size adds — the group count as a
/// line of its own and the largest groups as rows — rather than a third copy of the
/// state machine. Which hero, which figure, which action, where a tap goes: all of it
/// is the medium answer, so the two sizes cannot disagree about the same state.
///
/// A sibling of `WidgetComposition` instead of new fields on it, and no new
/// `WidgetLayoutFamily` case: both are shipped, and the extension's switch over the
/// family keeps working untouched.
public struct WidgetExtraLargeComposition: Equatable, Sendable {
    public let base: WidgetComposition
    /// «24 groups of similar photos», or `nil` when the count is unknown or the state
    /// has no figures to explain.
    public let clusterCountLine: String?
    /// The heading over `clusterRows`, `nil` exactly when there are no rows.
    public let rowsTitle: String?
    /// At most `WidgetSnapshot.topClustersLimit`, largest first. Empty for a state
    /// without figures and for a payload that predates `topClusters` — never a row of
    /// zeros.
    public let clusterRows: [WidgetClusterRow]
    public let accessibilityLabel: String

    public init(
        base: WidgetComposition,
        clusterCountLine: String?,
        rowsTitle: String?,
        clusterRows: [WidgetClusterRow],
        accessibilityLabel: String
    ) {
        self.base = base
        self.clusterCountLine = clusterCountLine
        self.rowsTitle = rowsTitle
        self.clusterRows = clusterRows
        self.accessibilityLabel = accessibilityLabel
    }
}

public extension WidgetPresentation {
    /// Resolves one display state into the extra-large portrait widget.
    ///
    /// Rows appear only for the states that show a figure — suggestions, a changed
    /// library, a review under way — because a list of groups under «All caught up» or
    /// «Open the app» would contradict the sentence above it.
    static func extraLargeComposition(
        for state: WidgetDisplayState,
        topClusters: [WidgetClusterSummary]?,
        clusterCount: Int? = nil
    ) -> WidgetExtraLargeComposition {
        let base = composition(for: state, family: .medium)

        let showsGroups: Bool
        let count: Int?
        switch state {
        case let .hasSuggestions(_, stateCount, _, _):
            showsGroups = true
            count = stateCount ?? clusterCount
        case .libraryChanged:
            showsGroups = true
            count = clusterCount
        case let .resumeReview(progress, _):
            showsGroups = true
            // The headline already reads «18 of 30 groups»; a second count would repeat it.
            count = progress.totalClusters > 0 ? nil : clusterCount
        case .unavailable, .noAccess, .neverScanned, .allCaughtUp:
            showsGroups = false
            count = nil
        }

        // The medium composition already carries the count as its detail line for
        // suggestions; the extra-large layout draws it once, here.
        let countLine = showsGroups ? (count.map { WidgetL10n.Status.similarGroups($0) }) : nil
        let rows = showsGroups
            ? WidgetClusterSummary.top(topClusters ?? []).map {
                WidgetClusterRow(
                    bytes: WidgetFormatting.approximateByteCount($0.reclaimableBytes),
                    photos: WidgetL10n.Library.photos($0.photoCount)
                )
            }
            : []
        let rowsTitle = rows.isEmpty ? nil : WidgetL10n.Status.largestGroups

        let label = [
            [base.headline, base.caption, countLine ?? base.detail?.text, base.footnote].compactMap { $0 },
            rows.map { "\($0.bytes), \($0.photos)" }
        ]
        .flatMap { $0 }
        .joined(separator: ", ")

        return WidgetExtraLargeComposition(
            base: base,
            clusterCountLine: countLine,
            rowsTitle: rowsTitle,
            clusterRows: rows,
            accessibilityLabel: label
        )
    }
}
