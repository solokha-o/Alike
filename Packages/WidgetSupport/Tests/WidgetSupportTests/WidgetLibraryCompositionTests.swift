import Foundation
import Testing
@testable import WidgetSupport

/// The library overview's three rows are three separate tap targets with three separate
/// units, and the layout that draws them lives in a target with no test action. Which
/// number goes on which row, which of them is locked, and where each one leads are all
/// decided in `libraryComposition(for:now:)` — here.
@Suite("Widget library composition")
struct WidgetLibraryCompositionTests {
    private static let scannedAt = Date(timeIntervalSince1970: 1_757_000_000)

    private func snapshot(
        authorization: WidgetPhotoAuthorization = .authorized,
        hasCompletedScan: Bool = true,
        lastScanDate: Date? = scannedAt,
        clusterCount: Int? = 24,
        screenshots: Int? = 86,
        blurred: Int? = 12,
        isPremium: Bool = true
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: Self.scannedAt,
            photoAuthorization: authorization,
            hasCompletedScan: hasCompletedScan,
            lastScanDate: lastScanDate,
            estimatedSavingsBytes: 1_932_735_283,
            clusterCount: clusterCount,
            screenshotAssetCount: screenshots,
            blurredPhotoAssetCount: blurred,
            isPremium: isPremium
        )
    }

    private func composition(_ snapshot: WidgetSnapshot?) -> WidgetLibraryComposition {
        WidgetPresentation.libraryComposition(for: snapshot, now: Self.scannedAt)
    }

    private func row(
        _ category: WidgetLibraryRow.Category,
        in composition: WidgetLibraryComposition
    ) throws -> WidgetLibraryRow {
        try #require(composition.rows.first { $0.category == category })
    }

    // MARK: - The three rows

    @Test("the overview is three rows, in the order the concept lists them")
    func rowOrder() {
        #expect(composition(snapshot()).rows.map(\.category) == [.similar, .screenshots, .blurredPhotos])
    }

    /// The symbols are named in the card, not read off the concept raster.
    @Test("each row carries the symbol the specification names")
    func symbols() throws {
        let resolved = composition(snapshot())

        #expect(try row(.similar, in: resolved).symbolName == "photo.stack")
        #expect(try row(.screenshots, in: resolved).symbolName == "camera.viewfinder")
        #expect(try row(.blurredPhotos, in: resolved).symbolName == "drop.triangle")
    }

    // MARK: - Groups are not photos

    /// Clusters are counted in groups and category candidates in photos. Rendering the
    /// same integer through the same plural for both would quietly claim the library
    /// holds 12 photos' worth of similar images when it holds 12 *groups* of them.
    @Test("the same number reads as groups on the similar row and as photos on the others")
    func groupsAreNotPhotos() throws {
        let resolved = composition(snapshot(clusterCount: 12, screenshots: 12, blurred: 12))

        let similar = try #require(try row(.similar, in: resolved).value)
        let screenshots = try #require(try row(.screenshots, in: resolved).value)

        #expect(similar == WidgetL10n.Status.groups(12))
        #expect(screenshots == WidgetL10n.Library.photos(12))
        #expect(similar != screenshots)
    }

    /// The card is explicit that the two units are never added together. A row showing
    /// 122 would be exactly that mistake.
    @Test("no row shows the sum of the other rows")
    func noAggregate() {
        let resolved = composition(snapshot(clusterCount: 24, screenshots: 86, blurred: 12))
        let forbidden = [WidgetL10n.Status.groups(122), WidgetL10n.Library.photos(122),
                         WidgetL10n.Library.photos(98), WidgetL10n.Status.groups(98)]

        for value in resolved.rows.compactMap(\.value) {
            #expect(!forbidden.contains(value), "a row aggregated groups with photos: \(value)")
        }
    }

    // MARK: - Unknown is not zero

    /// `nil` in the snapshot means the app has not measured this, which is not the same
    /// claim as "there are none". The row stays — it is still a working way into that
    /// list — but it shows no figure.
    @Test("an unknown count leaves the row without a figure rather than showing zero")
    func unknownCountDrawsNoFigure() throws {
        let resolved = composition(snapshot(clusterCount: nil, screenshots: nil, blurred: nil))

        #expect(resolved.rows.count == 3)
        for row in resolved.rows {
            #expect(row.value == nil, "\(row.category) invented a figure for an unknown count")
            #expect(!row.accessibilityLabel.contains("0"), "\(row.category) read out a fabricated zero")
        }
    }

    @Test("a genuine zero is still a figure and is shown")
    func zeroIsShown() throws {
        let resolved = composition(snapshot(clusterCount: 0, screenshots: 0, blurred: 0))

        #expect(try row(.screenshots, in: resolved).value == WidgetL10n.Library.photos(0))
    }

    // MARK: - Routing

    /// The acceptance criterion the widget exists for: three rows, three lists.
    @Test("each row leads to its own list")
    func rowDestinations() throws {
        let resolved = composition(snapshot())

        #expect(try row(.similar, in: resolved).destination == .similarPhotos)
        #expect(try row(.screenshots, in: resolved).destination == .screenshots)
        #expect(try row(.blurredPhotos, in: resolved).destination == .blurredPhotos)
        #expect(Set(resolved.rows.map(\.destination)).count == 3)
    }

    /// The area around the rows is not a fourth category; it is the way into cleanup.
    @Test("the widget as a whole falls back to cleanup")
    func widgetDestination() {
        #expect(composition(snapshot()).destination == .cleanup)
    }

    // MARK: - Premium

    /// The extension links neither `Purchases` nor StoreKit, so `isPremium` is a copy of
    /// what the app last knew. It may draw a lock; it may not decide the route. The row
    /// keeps its own destination and the app re-checks the live entitlement on arrival.
    @Test("a locked row keeps its own destination — the widget never routes to a paywall")
    func lockedRowsKeepTheirDestination() throws {
        let resolved = composition(snapshot(isPremium: false))

        #expect(try row(.screenshots, in: resolved).destination == .screenshots)
        #expect(try row(.blurredPhotos, in: resolved).destination == .blurredPhotos)
    }

    @Test("without premium the two gated categories are locked and similar photos are not")
    func lockedCategories() throws {
        let resolved = composition(snapshot(isPremium: false))

        #expect(try row(.similar, in: resolved).isLocked == false)
        #expect(try row(.screenshots, in: resolved).isLocked)
        #expect(try row(.blurredPhotos, in: resolved).isLocked)
    }

    @Test("with premium nothing is locked")
    func nothingLockedForSubscribers() {
        #expect(composition(snapshot(isPremium: true)).rows.allSatisfy { !$0.isLocked })
    }

    /// The counts are computed independently of entitlement, and the card decides they
    /// are shown to everyone. Hiding them would make the widget useless as a reason to
    /// subscribe.
    @Test("the figures are the same with and without premium")
    func figuresDoNotDependOnEntitlement() {
        #expect(composition(snapshot(isPremium: false)).rows.map(\.value)
            == composition(snapshot(isPremium: true)).rows.map(\.value))
    }

    // MARK: - States with nothing to list

    @Test(
        "a state with nothing measured shows one sentence and no rows",
        arguments: [
            (WidgetSnapshot?.none, "no snapshot"),
            (WidgetSnapshot?.some(WidgetSnapshot(generatedAt: scannedAt, photoAuthorization: .denied, hasCompletedScan: true)), "denied"),
            (WidgetSnapshot?.some(WidgetSnapshot(generatedAt: scannedAt, photoAuthorization: .notDetermined, hasCompletedScan: false)), "not determined"),
            (WidgetSnapshot?.some(WidgetSnapshot(generatedAt: scannedAt, photoAuthorization: .authorized, hasCompletedScan: false)), "never scanned")
        ]
    )
    func degenerateStates(snapshot: WidgetSnapshot?, name: String) throws {
        let resolved = composition(snapshot)

        #expect(resolved.rows.isEmpty, "\(name) listed rows it has no figures for")
        #expect(!(try #require(resolved.caption)).isEmpty, "\(name) has nothing to say")
        #expect(resolved.footnote == nil, "\(name) dated figures it does not have")
        #expect(resolved.destination == .cleanup)
    }

    @Test("a library the app cannot read asks for access instead of listing anything")
    func deniedAsksForAccess() {
        #expect(composition(snapshot(authorization: .denied)).caption == WidgetL10n.Status.noAccess)
    }

    /// `.limited` grants library access, so the counts it produced are real counts of
    /// the photos the app was given — the widget lists them rather than treating a
    /// partly-shared library as no library.
    @Test("a limited library still shows the counts it measured")
    func limitedStillCounts() {
        let resolved = composition(snapshot(authorization: .limited))

        #expect(resolved.caption == nil)
        #expect(resolved.rows.count == 3)
    }

    // MARK: - Dating the figures

    /// Three counts with no date read as this minute's. The widget cannot refresh itself
    /// — the timeline policy is `.never` — so the date travels with the figures always,
    /// not only once they cross the staleness threshold.
    @Test("the figures are dated whenever the snapshot knows when they were measured")
    func footnoteDatesTheFigures() throws {
        let resolved = composition(snapshot())
        let expected = WidgetL10n.Status.lastScanned(
            WidgetFormatting.timestamp(Self.scannedAt, timeStyle: .omitted)
        )

        #expect(resolved.footnote == expected)
        #expect(resolved.accessibilityLabel.contains(try #require(resolved.footnote)))
    }

    @Test("an unknown scan date leaves the figures undated rather than guessing")
    func noScanDateNoFootnote() {
        #expect(composition(snapshot(lastScanDate: nil)).footnote == nil)
    }

    // MARK: - Hero

    /// `WidgetHeroAssetsTests` proves the files exist; this proves the composition only
    /// asks for those. A scene with no file renders as a hole in the widget.
    @Test("every hero the overview names is one the bundle carries")
    func heroesAreResolvable() {
        let snapshots: [WidgetSnapshot?] = [
            nil, snapshot(), snapshot(clusterCount: 0, screenshots: 0, blurred: 0),
            snapshot(clusterCount: nil, screenshots: nil, blurred: nil),
            snapshot(hasCompletedScan: false), snapshot(authorization: .denied)
        ]

        for candidate in snapshots {
            guard let hero = composition(candidate).hero else { continue }
            #expect(WidgetHeroAssets.url(for: hero, scale: .twoX) != nil, "names an unbundled hero")
        }
    }

    /// Nothing left anywhere is the one case that has earned the "all caught up" scene.
    @Test("an empty library gets the caught-up scene and a full one does not")
    func heroFollowsTheCounts() {
        #expect(composition(snapshot(clusterCount: 0, screenshots: 0, blurred: 0)).hero == .allCaughtUp)
        #expect(composition(snapshot()).hero == .hasReviews)
    }

    /// Unknown counts have not established that there is nothing; claiming otherwise
    /// would put a "you're done" illustration over a library nobody has looked at.
    @Test("unknown counts do not earn the caught-up scene")
    func unknownIsNotCaughtUp() {
        #expect(composition(snapshot(clusterCount: nil, screenshots: nil, blurred: nil)).hero == .hasReviews)
    }

    // MARK: - Accessibility

    @Test("no row is left without something to read out")
    func everyRowSpeaks() {
        for isPremium in [true, false] {
            for row in composition(snapshot(isPremium: isPremium)).rows {
                #expect(!row.title.isEmpty, "\(row.category) has no title")
                #expect(!row.accessibilityLabel.isEmpty, "\(row.category) has nothing to read out")
                #expect(!row.accessibilityHint.isEmpty, "\(row.category) has no hint")
            }
        }
    }

    /// The lock is a glyph on screen and nothing at all to VoiceOver unless it is said.
    /// Without it, a row that opens a paywall is announced exactly like one that opens
    /// the list its label names.
    @Test("a locked row says so, and says it opens something other than the list")
    func lockIsAnnounced() throws {
        let locked = try row(.screenshots, in: composition(snapshot(isPremium: false)))
        let unlocked = try row(.screenshots, in: composition(snapshot(isPremium: true)))

        #expect(locked.accessibilityLabel.contains(WidgetL10n.Library.locked))
        #expect(!unlocked.accessibilityLabel.contains(WidgetL10n.Library.locked))
        #expect(locked.accessibilityHint != unlocked.accessibilityHint)
    }

    @Test("a row reads out its own figure")
    func rowLabelCarriesTheFigure() throws {
        let resolved = try row(.screenshots, in: composition(snapshot(screenshots: 86)))

        #expect(resolved.accessibilityLabel.contains(resolved.title))
        #expect(resolved.accessibilityLabel.contains(try #require(resolved.value)))
    }

    // MARK: - Timeline

    /// The second entry exists so the figures stop being presented as current without
    /// spending a refresh budget. It is scheduled on the same threshold as the status
    /// widget's, from the same arithmetic.
    @Test("the timeline starts now and never schedules an entry in the past")
    func timelineShape() throws {
        let steps = WidgetPresentation.libraryTimeline(for: snapshot(), now: Self.scannedAt)

        #expect(steps.first?.date == Self.scannedAt)
        #expect(steps.allSatisfy { $0.date >= Self.scannedAt })
        #expect(steps.map(\.date) == steps.map(\.date).sorted())
    }

    @Test("a missing snapshot has one entry and nothing to schedule")
    func timelineWithoutSnapshot() {
        #expect(WidgetPresentation.libraryTimeline(for: nil, now: Self.scannedAt).count == 1)
    }
}
