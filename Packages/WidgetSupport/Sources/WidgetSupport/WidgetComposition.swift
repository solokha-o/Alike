import Foundation

/// Which of the two widget sizes is being drawn.
///
/// The package's own enum rather than WidgetKit's `WidgetFamily`: `WidgetSupport`
/// links nothing, which is what lets it be tested in its own workspace, and the
/// extension does the one-line mapping. Only the two families the widget supports
/// appear here — an unsupported family is a case that cannot arrive.
public enum WidgetLayoutFamily: String, CaseIterable, Sendable {
    case small
    case medium
}

/// Everything a widget layout needs, already decided.
///
/// The views live in the extension target, which has no test action, so they are kept
/// free of judgement: which hero, which wording, which number, where a tap goes and
/// what VoiceOver hears are all resolved here, where `WidgetCompositionTests` can reach
/// them. A layout's only remaining job is to place these values.
public struct WidgetComposition: Equatable, Sendable {
    /// The illustration, or `nil` when the state has nothing to illustrate and the
    /// words should carry it alone.
    public let hero: WidgetHeroScene?
    public let symbolName: String
    /// The big figure — `nil` when there is no honest one to show.
    ///
    /// An unknown byte count renders as no headline rather than as "0 bytes": the
    /// snapshot's optionals mean *unknown*, and a fabricated zero would read as a
    /// measured result.
    public let headline: String?
    public let caption: String
    /// The group count when the figures are current, the scan date when they are not.
    public let footnote: String?
    /// What opening the app leads to, as a label rather than a control — a widget tap
    /// opens the app; nothing here is a button.
    public let actionTitle: String?
    /// Reviewed groups over total groups, or `nil` when there is no real fraction.
    public let progress: Double?
    public let destination: WidgetDestination
    public let accessibilityLabel: String
    public let accessibilityHint: String

    public init(
        hero: WidgetHeroScene?,
        symbolName: String,
        headline: String?,
        caption: String,
        footnote: String?,
        actionTitle: String?,
        progress: Double?,
        destination: WidgetDestination,
        accessibilityLabel: String,
        accessibilityHint: String
    ) {
        self.hero = hero
        self.symbolName = symbolName
        self.headline = headline
        self.caption = caption
        self.footnote = footnote
        self.actionTitle = actionTitle
        self.progress = progress
        self.destination = destination
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
    }
}

public extension WidgetPresentation {
    /// Resolves one display state and one size into the content of a widget.
    ///
    /// The medium layout is not a bigger small layout: it has the room to name what the
    /// groups are groups of, to keep the group count *and* the scan date side by side,
    /// and to show an illustration for states the small layout gives all its space to
    /// text. Those differences are decided here rather than by two views drifting apart.
    static func composition(
        for state: WidgetDisplayState,
        family: WidgetLayoutFamily
    ) -> WidgetComposition {
        let destination = destination(for: state)

        switch state {
        case .unavailable:
            return composition(
                hero: nil,
                symbol: "lock.fill",
                headline: nil,
                caption: WidgetL10n.Status.openApp,
                footnote: nil,
                action: nil,
                destination: destination
            )

        case let .noAccess(status):
            return composition(
                hero: nil,
                symbol: "lock.fill",
                headline: nil,
                caption: status == .limited ? WidgetL10n.Status.limitedAccess : WidgetL10n.Status.noAccess,
                footnote: nil,
                action: nil,
                destination: destination
            )

        case .neverScanned:
            return composition(
                // Nothing has been measured yet, so the medium layout's spare room goes
                // to the "ready to scan" illustration rather than to blank space. The
                // small layout keeps every point for the sentence that explains itself.
                hero: family == .medium ? .hasReviews : nil,
                symbol: "viewfinder",
                headline: nil,
                caption: WidgetL10n.Status.scanPrompt,
                footnote: nil,
                action: WidgetL10n.Action.scan,
                destination: destination
            )

        case let .allCaughtUp(scannedAt):
            return composition(
                hero: .allCaughtUp,
                symbol: "checkmark.circle.fill",
                headline: nil,
                caption: WidgetL10n.Status.allCaughtUp,
                footnote: scannedAt.map(scannedFootnote),
                action: nil,
                destination: destination
            )

        case let .hasSuggestions(bytes, clusterCount, scannedAt, isStale):
            return composition(
                hero: .hasReviews,
                symbol: "photo.stack",
                // Verbatim `WidgetSnapshot.estimatedSavingsBytes`. The widget has no
                // estimate of its own, so it cannot disagree with the scanner screen.
                headline: bytes.map { WidgetFormatting.byteCount($0) },
                caption: WidgetL10n.Status.reclaimable,
                footnote: suggestionsFootnote(
                    clusterCount: clusterCount,
                    scannedAt: scannedAt,
                    isStale: isStale,
                    family: family
                ),
                action: WidgetL10n.Action.review,
                destination: destination
            )

        case let .libraryChanged(bytes, scannedAt):
            return composition(
                hero: .hasReviews,
                symbol: "arrow.triangle.2.circlepath",
                headline: bytes.map { WidgetFormatting.byteCount($0) },
                caption: WidgetL10n.Status.libraryChanged,
                // The figures are historical by definition here, so the date travels
                // with them whatever the staleness threshold says.
                footnote: scannedAt.map(scannedFootnote),
                action: WidgetL10n.Action.review,
                destination: destination
            )

        case let .resumeReview(progress, isStale):
            return resumeComposition(
                progress: progress,
                isStale: isStale,
                family: family,
                destination: destination
            )
        }
    }
}

private extension WidgetPresentation {
    static func scannedFootnote(_ date: Date) -> String {
        WidgetL10n.Status.lastScanned(WidgetFormatting.timestamp(date, timeStyle: .omitted))
    }

    /// The group count while the figures are current, the scan date once they are not.
    ///
    /// The count is medium's: the small composition is the figure, what it is, and where
    /// a tap goes, and a second number competing with the first is what makes a small
    /// widget unreadable. Staleness is the one thing small does not get to drop — a
    /// figure shown without saying when it was measured reads as today's — so on small
    /// the date replaces the action line, and on medium it joins the count.
    static func suggestionsFootnote(
        clusterCount: Int?,
        scannedAt: Date?,
        isStale: Bool,
        family: WidgetLayoutFamily
    ) -> String? {
        let scanned = isStale ? scannedAt.map(scannedFootnote) : nil
        guard family == .medium else { return scanned }

        guard let groups = clusterCount.map({ WidgetL10n.Status.similarGroups($0) }) else { return scanned }
        guard let scanned else { return groups }
        return "\(groups) · \(scanned)"
    }

    static func resumeComposition(
        progress: WidgetSessionProgress,
        isStale: Bool,
        family: WidgetLayoutFamily,
        destination: WidgetDestination
    ) -> WidgetComposition {
        // Reviewed groups over total groups — groups, not photos deleted, and not a
        // fraction invented for a session that has not been sized yet. `fraction`
        // already guards the divide; `nil` here keeps the layout from drawing an empty
        // bar that would read as "nothing reviewed" when the truth is "not known".
        let fraction = progress.totalClusters > 0 ? progress.fraction : nil
        let headline = progress.totalClusters > 0
            ? "\(WidgetFormatting.number(progress.reviewedClusters))/\(WidgetFormatting.number(progress.totalClusters))"
            : nil

        // Same split as the cleanup footnote: how many groups are left is medium's line,
        // small keeps the bar and the way back in. Staleness overrides on both.
        let footnote: String? = if isStale {
            scannedFootnote(progress.updatedAt)
        } else if family == .medium, progress.totalClusters > 0 {
            WidgetL10n.Status.groupsRemaining(progress.remainingClusters)
        } else {
            nil
        }

        return composition(
            hero: .comparisonReview,
            symbol: "rectangle.on.rectangle",
            headline: headline,
            caption: family == .medium ? WidgetL10n.Status.continueReview : WidgetL10n.Status.groupsReviewed,
            footnote: footnote,
            action: WidgetL10n.Action.continueReview,
            progress: fraction,
            destination: destination,
            hint: WidgetL10n.Accessibility.resumeReview
        )
    }

    static func composition(
        hero: WidgetHeroScene?,
        symbol: String,
        headline: String?,
        caption: String,
        footnote: String?,
        action: String?,
        progress: Double? = nil,
        destination: WidgetDestination,
        hint: String = WidgetL10n.Accessibility.openCleanup
    ) -> WidgetComposition {
        WidgetComposition(
            hero: hero,
            symbolName: symbol,
            headline: headline,
            caption: caption,
            footnote: footnote,
            actionTitle: action,
            progress: progress,
            destination: destination,
            accessibilityLabel: accessibilityLabel(headline: headline, caption: caption, footnote: footnote),
            accessibilityHint: hint
        )
    }

    /// One sentence: the figure, what it is, and when it was measured.
    ///
    /// The footnote is part of the label, not decoration around it. Leaving it out is
    /// how VoiceOver ended up reading a day-old figure as the current one, which
    /// `46f405b` fixed for the one layout that existed then; building the label here
    /// keeps four layouts from each having to remember.
    static func accessibilityLabel(headline: String?, caption: String, footnote: String?) -> String {
        [headline, caption, footnote].compactMap { $0 }.joined(separator: ", ")
    }
}
