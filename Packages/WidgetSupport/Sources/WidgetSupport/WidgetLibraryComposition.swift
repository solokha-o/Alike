import Foundation

/// One category line of the library overview.
///
/// A row is its own tap target, which is what separates this composition from
/// ``WidgetComposition``: that one carries a single `destination` applied to the whole
/// widget through `widgetURL`, and three lines that each open a different list cannot be
/// expressed that way. The layout draws these as `Link`s.
public struct WidgetLibraryRow: Equatable, Sendable, Identifiable {
    /// What the row counts. Deliberately not `CleanupCategoryKind`: there is no
    /// "similar" category — similar photos are clusters, and the two are counted in
    /// different units. `WidgetSupport` links nothing, so it cannot see that type anyway.
    public enum Category: String, CaseIterable, Sendable {
        case similar
        case screenshots
        case blurredPhotos
    }

    public let category: Category
    public let symbolName: String
    public let title: String
    /// The formatted count, or `nil` when the snapshot does not know it.
    ///
    /// `nil` is *unknown*, not zero. A row without a figure still links into its list;
    /// a fabricated "0" would read as a measured result.
    public let value: String?
    /// Whether to draw the lock glyph.
    ///
    /// Presentation only. The row keeps its own destination either way: the extension
    /// links neither `Purchases` nor StoreKit, so the snapshot's `isPremium` is a
    /// day-old copy at best. Whether the tap lands on the list or on the paywall is
    /// decided in the app, against the live entitlement, by the gate that already
    /// exists there.
    public let isLocked: Bool
    public let destination: WidgetDestination
    public let accessibilityLabel: String
    public let accessibilityHint: String

    public var id: Category { category }

    public init(
        category: Category,
        symbolName: String,
        title: String,
        value: String?,
        isLocked: Bool,
        destination: WidgetDestination,
        accessibilityLabel: String,
        accessibilityHint: String
    ) {
        self.category = category
        self.symbolName = symbolName
        self.title = title
        self.value = value
        self.isLocked = isLocked
        self.destination = destination
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
    }
}

/// Everything the `systemMedium` library layout needs, already decided.
///
/// Same division of labour as ``WidgetComposition``: the view in the extension target
/// places these values and decides nothing, because that target has no test action.
public struct WidgetLibraryComposition: Equatable, Sendable {
    public let hero: WidgetHeroScene?
    /// The three category lines, or empty when there is nothing measured to list.
    public let rows: [WidgetLibraryRow]
    /// The sentence shown in place of the rows — never alongside them.
    public let caption: String?
    /// When the figures were measured. Present whenever the snapshot knows, not only
    /// once they are stale: three counts with no date read as this minute's.
    public let footnote: String?
    /// Where the area *around* the rows leads, applied by the layout as `widgetURL`.
    public let destination: WidgetDestination
    /// Read out for the widget as a whole; each row carries its own label as well.
    public let accessibilityLabel: String
    public let accessibilityHint: String

    public init(
        hero: WidgetHeroScene?,
        rows: [WidgetLibraryRow],
        caption: String?,
        footnote: String?,
        destination: WidgetDestination,
        accessibilityLabel: String,
        accessibilityHint: String
    ) {
        self.hero = hero
        self.rows = rows
        self.caption = caption
        self.footnote = footnote
        self.destination = destination
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
    }
}

/// One rendering of the library widget and the moment WidgetKit should switch to it.
public struct WidgetLibraryTimelineStep: Equatable, Sendable {
    public let date: Date
    public let composition: WidgetLibraryComposition

    public init(date: Date, composition: WidgetLibraryComposition) {
        self.date = date
        self.composition = composition
    }
}

public extension WidgetPresentation {
    /// Resolves a snapshot into the three-row library overview.
    ///
    /// Takes the snapshot rather than a ``WidgetDisplayState`` because the counts this
    /// composition is made of — screenshots, blurred photos, the premium flag — are not
    /// in that state, and widening a shipped enum to carry them would change a type the
    /// installed widgets already switch over. The degenerate cases still go through
    /// `displayState(for:now:)`, so there is one precedence ladder, not two.
    static func libraryComposition(
        for snapshot: WidgetSnapshot?,
        now: Date = Date()
    ) -> WidgetLibraryComposition {
        switch displayState(for: snapshot, now: now) {
        case .unavailable:
            return placeholder(caption: WidgetL10n.Status.openApp, hero: nil)

        case let .noAccess(status):
            // `.limited` grants library access today, so this arm only ever sees denied,
            // restricted and not-determined. The limited wording is kept in step with
            // the status widget's rather than folded away: which authorizations count as
            // access is `WidgetPhotoAuthorization`'s decision, not this composition's.
            return placeholder(
                caption: status == .limited ? WidgetL10n.Status.limitedAccess : WidgetL10n.Status.noAccess,
                hero: nil
            )

        case .neverScanned:
            return placeholder(caption: WidgetL10n.Status.scanPrompt, hero: .hasReviews)

        case .allCaughtUp, .hasSuggestions, .libraryChanged, .resumeReview:
            // Every one of these has been scanned at least once, which is the only
            // condition for the counts being worth listing. Which of them it is changes
            // the *other* widget's wording, not this one's: the rows say what is in the
            // library, and that is the same sentence whether or not a review is open.
            guard let snapshot else { return placeholder(caption: WidgetL10n.Status.openApp, hero: nil) }
            return overview(for: snapshot)
        }
    }

    /// The library widget's timeline: what to show now, plus the moment the figures stop
    /// being presentable as current.
    ///
    /// Mirrors ``timeline(for:now:)`` deliberately — the two widgets go stale on the same
    /// threshold, and duplicating the date arithmetic in the extension would put it
    /// somewhere no test can reach.
    static func libraryTimeline(
        for snapshot: WidgetSnapshot?,
        now: Date = Date()
    ) -> [WidgetLibraryTimelineStep] {
        var steps = [WidgetLibraryTimelineStep(date: now, composition: libraryComposition(for: snapshot, now: now))]

        if let snapshot {
            let staleDate = staleDate(for: snapshot)
            let staleComposition = libraryComposition(for: snapshot, now: staleDate)
            if staleDate > now, staleComposition != steps[0].composition {
                steps.append(WidgetLibraryTimelineStep(date: staleDate, composition: staleComposition))
            }
        }

        return steps
    }
}

private extension WidgetPresentation {
    /// A state with nothing measured to list: one sentence, no rows, no invented counts.
    static func placeholder(caption: String, hero: WidgetHeroScene?) -> WidgetLibraryComposition {
        WidgetLibraryComposition(
            hero: hero,
            rows: [],
            caption: caption,
            footnote: nil,
            destination: .cleanup,
            accessibilityLabel: caption,
            accessibilityHint: WidgetL10n.Accessibility.openCleanup
        )
    }

    static func overview(for snapshot: WidgetSnapshot) -> WidgetLibraryComposition {
        let rows = [
            // Clusters, counted in groups. There is no "similar" category to read a
            // photo count off, and summing groups with photos would produce a figure
            // that means nothing.
            row(
                category: .similar,
                symbol: "photo.stack",
                title: WidgetL10n.Library.similar,
                value: snapshot.clusterCount.map { WidgetL10n.Status.groups($0) },
                isLocked: false,
                destination: .similarPhotos
            ),
            row(
                category: .screenshots,
                symbol: "camera.viewfinder",
                title: WidgetL10n.Library.screenshots,
                value: snapshot.screenshotAssetCount.map { WidgetL10n.Library.photos($0) },
                isLocked: !snapshot.isPremium,
                destination: .screenshots
            ),
            row(
                category: .blurredPhotos,
                symbol: "drop.triangle",
                title: WidgetL10n.Library.blurred,
                value: snapshot.blurredPhotoAssetCount.map { WidgetL10n.Library.photos($0) },
                isLocked: !snapshot.isPremium,
                destination: .blurredPhotos
            )
        ]

        let footnote = snapshot.lastScanDate.map {
            WidgetL10n.Status.lastScanned(WidgetFormatting.timestamp($0, timeStyle: .omitted))
        }

        return WidgetLibraryComposition(
            hero: hero(for: snapshot),
            rows: rows,
            caption: nil,
            footnote: footnote,
            destination: .cleanup,
            // The rows are `Link`s and read themselves out; what is left for the widget
            // as a whole is when the figures were measured, which otherwise belongs to
            // no element at all.
            accessibilityLabel: [WidgetL10n.Widget.libraryDisplayName, footnote]
                .compactMap { $0 }
                .joined(separator: ", "),
            accessibilityHint: WidgetL10n.Accessibility.openCleanup
        )
    }

    /// Reviews waiting, unless every count the snapshot knows is zero.
    ///
    /// Unknown counts do not make it "all caught up": a snapshot that knows nothing has
    /// not established that there is nothing.
    static func hero(for snapshot: WidgetSnapshot) -> WidgetHeroScene {
        let known = [
            snapshot.clusterCount,
            snapshot.screenshotAssetCount,
            snapshot.blurredPhotoAssetCount
        ].compactMap { $0 }

        return known.isEmpty || known.contains(where: { $0 > 0 }) ? .hasReviews : .allCaughtUp
    }

    static func row(
        category: WidgetLibraryRow.Category,
        symbol: String,
        title: String,
        value: String?,
        isLocked: Bool,
        destination: WidgetDestination
    ) -> WidgetLibraryRow {
        WidgetLibraryRow(
            category: category,
            symbolName: symbol,
            title: title,
            value: value,
            isLocked: isLocked,
            destination: destination,
            // The lock is part of the sentence, not decoration around it: a locked row
            // opens a paywall rather than the list its label names, and VoiceOver has
            // no other way to be told.
            accessibilityLabel: [title, value, isLocked ? WidgetL10n.Library.locked : nil]
                .compactMap { $0 }
                .joined(separator: ", "),
            accessibilityHint: isLocked
                ? WidgetL10n.Accessibility.unlockCategory
                : WidgetL10n.Accessibility.openList
        )
    }
}
