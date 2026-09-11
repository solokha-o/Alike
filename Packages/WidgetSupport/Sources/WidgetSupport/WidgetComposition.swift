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

/// The big figure split the way the concept draws it: the number in the accent colour,
/// the rest beside it in the text colour — «≈1,8 ГБ» alone, or «18» followed by «із 30».
///
/// `WidgetComposition.headline` stays the flat sentence VoiceOver reads; this is the same
/// text in the two pieces the layout colours differently.
public struct WidgetHeadlineParts: Equatable, Sendable {
    public let accent: String
    public let rest: String?

    public init(accent: String, rest: String? = nil) {
        self.accent = accent
        self.rest = rest
    }

    /// The two pieces as one line, which is what the flat headline carries.
    public var joined: String {
        [accent, rest].compactMap { $0 }.joined(separator: " ")
    }
}

/// One list line under the figure — «24 групи схожих фото» with its own glyph.
///
/// Only the medium layout has the room for it, and it is a line of its own rather than
/// the footnote: the footnote is reserved for the date of a stale figure.
public struct WidgetDetailLine: Equatable, Sendable {
    public let symbolName: String
    public let text: String

    public init(symbolName: String, text: String) {
        self.symbolName = symbolName
        self.text = text
    }
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
    /// `headline` in the pieces the layout colours differently, or `nil` when there is
    /// no figure.
    public let headlineParts: WidgetHeadlineParts?
    public let caption: String
    /// The list line under the figure, medium only.
    public let detail: WidgetDetailLine?
    /// The group count when the figures are current, the date they were measured when
    /// they are not — the scan date for the cleanup states, the session's own date for
    /// a resumed review.
    public let footnote: String?
    /// What opening the app leads to, as a label rather than a control — a widget tap
    /// opens the app; nothing here is a button.
    public let actionTitle: String?
    /// Reviewed groups over total groups, or `nil` when there is no real fraction.
    public let progress: Double?
    public let destination: WidgetDestination
    public let accessibilityLabel: String
    public let accessibilityHint: String
    /// The glyph drawn beside the wordmark, only for the states that have no figure to
    /// carry the widget. A state with a headline returns `nil`: the concept puts the
    /// «Alike» wordmark there, and a glyph next to it would be a second brand mark.
    public let headerSymbolName: String?

    public init(
        hero: WidgetHeroScene?,
        symbolName: String,
        headline: String?,
        headlineParts: WidgetHeadlineParts? = nil,
        caption: String,
        detail: WidgetDetailLine? = nil,
        footnote: String?,
        actionTitle: String?,
        progress: Double?,
        destination: WidgetDestination,
        accessibilityLabel: String,
        accessibilityHint: String,
        headerSymbolName: String? = nil
    ) {
        self.hero = hero
        self.symbolName = symbolName
        self.headline = headline
        self.headlineParts = headlineParts
        self.caption = caption
        self.detail = detail
        self.footnote = footnote
        self.actionTitle = actionTitle
        self.progress = progress
        self.destination = destination
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.headerSymbolName = headerSymbolName
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
                // Verbatim `WidgetSnapshot.estimatedSavingsBytes`, prefixed «≈» as the
                // concept spells it. The widget has no estimate of its own, so it
                // cannot disagree with the scanner screen.
                headline: bytes.map { WidgetHeadlineParts(accent: WidgetFormatting.approximateByteCount($0)) },
                caption: WidgetL10n.Status.reclaimable,
                detail: detail(clusterCount: clusterCount, family: family),
                // The count has its own line now; the footnote is the date, and only
                // once the figure is old enough to need one.
                footnote: isStale ? scannedAt.map(scannedFootnote) : nil,
                action: WidgetL10n.Action.review,
                destination: destination
            )

        case let .libraryChanged(bytes, scannedAt):
            return composition(
                hero: .hasReviews,
                symbol: "arrow.triangle.2.circlepath",
                headline: bytes.map { WidgetHeadlineParts(accent: WidgetFormatting.approximateByteCount($0)) },
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

    /// The session's own date, worded as a review rather than as a scan.
    ///
    /// `WidgetSessionProgress.updatedAt` is when the review was last touched, and the
    /// scan it belongs to can be days older — `WidgetSnapshot.lastScanDate` carries
    /// that separately. Labelling `updatedAt` "Scanned" would date the scan wrong and
    /// the session right, in one line, to VoiceOver as well as on screen.
    static func reviewedFootnote(_ date: Date) -> String {
        WidgetL10n.Status.lastReviewed(WidgetFormatting.timestamp(date, timeStyle: .omitted))
    }

    /// «24 групи схожих фото» as a line of its own, medium only.
    ///
    /// The small composition is the figure, what it is, and where a tap goes; a second
    /// number competing with the first is what makes a small widget unreadable.
    static func detail(clusterCount: Int?, family: WidgetLayoutFamily) -> WidgetDetailLine? {
        guard family == .medium, let clusterCount else { return nil }
        return WidgetDetailLine(symbolName: "photo.stack", text: WidgetL10n.Status.similarGroups(clusterCount))
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
        // «18 із 30» on small, «18 із 30 груп» on medium — the reviewed count in the
        // accent colour, the total beside it, as the concept draws it.
        let headline: WidgetHeadlineParts? = progress.totalClusters > 0
            ? WidgetHeadlineParts(
                accent: WidgetFormatting.number(progress.reviewedClusters),
                rest: family == .medium
                    ? WidgetL10n.Status.ofGroups(progress.totalClusters)
                    : WidgetL10n.Status.ofTotal(progress.totalClusters)
            )
            : nil

        // Medium names the groups left under the figure; small, where the total is
        // already in the headline, says what the figure counts. The footnote is the
        // session date, and only once it is stale.
        let caption = family == .medium && progress.totalClusters > 0
            ? WidgetL10n.Status.groupsRemaining(progress.remainingClusters)
            : WidgetL10n.Status.groupsReviewed
        let footnote = isStale ? reviewedFootnote(progress.updatedAt) : nil

        return composition(
            hero: .comparisonReview,
            symbol: "rectangle.on.rectangle",
            headline: headline,
            caption: caption,
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
        headline: WidgetHeadlineParts?,
        caption: String,
        detail: WidgetDetailLine? = nil,
        footnote: String?,
        action: String?,
        progress: Double? = nil,
        destination: WidgetDestination,
        hint: String = WidgetL10n.Accessibility.openCleanup
    ) -> WidgetComposition {
        let flatHeadline = headline?.joined
        return WidgetComposition(
            hero: hero,
            symbolName: symbol,
            headline: flatHeadline,
            headlineParts: headline,
            caption: caption,
            detail: detail,
            footnote: footnote,
            actionTitle: action,
            progress: progress,
            destination: destination,
            accessibilityLabel: accessibilityLabel(
                headline: flatHeadline, caption: caption, detail: detail?.text, footnote: footnote
            ),
            accessibilityHint: hint,
            // The wordmark takes the header once there is a figure; the glyph is for
            // the states that have only a sentence.
            headerSymbolName: headline == nil ? symbol : nil
        )
    }

    /// One sentence: the figure, what it is, and when it was measured.
    ///
    /// The footnote is part of the label, not decoration around it. Leaving it out is
    /// how VoiceOver ended up reading a day-old figure as the current one, which
    /// `46f405b` fixed for the one layout that existed then; building the label here
    /// keeps four layouts from each having to remember.
    static func accessibilityLabel(headline: String?, caption: String, detail: String?, footnote: String?) -> String {
        [headline, caption, detail, footnote].compactMap { $0 }.joined(separator: ", ")
    }
}
