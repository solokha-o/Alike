import Foundation
import Testing
@testable import WidgetSupport

/// Everything the four widget layouts decide is decided in `composition(for:family:)`,
/// because the extension target has no test action. These are the tests the views cannot
/// have: which hero, which wording, which number, where a tap goes, and what VoiceOver
/// is left with.
@Suite("Widget composition")
struct WidgetCompositionTests {
    private static let scannedAt = Date(timeIntervalSince1970: 1_757_000_000)
    /// Two days after `scannedAt`: the session outlives the scan it belongs to, and the
    /// widget has to keep the two dates apart.
    private static let reviewedAt = scannedAt.addingTimeInterval(2 * 24 * 60 * 60)
    private static let families = WidgetLayoutFamily.allCases

    private func composition(
        _ state: WidgetDisplayState,
        _ family: WidgetLayoutFamily
    ) -> WidgetComposition {
        WidgetPresentation.composition(for: state, family: family)
    }

    // MARK: - The number

    /// The widget has no estimate of its own. It prints the snapshot's bytes and nothing
    /// else — behind the «≈» the concept draws — so it cannot end up disagreeing with the
    /// scanner screen.
    @Test("the headline is the snapshot's byte count, formatted and not recomputed", arguments: families)
    func headlineEchoesBytes(family: WidgetLayoutFamily) {
        let bytes: Int64 = 1_932_735_283
        let state = WidgetDisplayState.hasSuggestions(
            bytes: bytes, clusterCount: 24, scannedAt: Self.scannedAt, isStale: false
        )
        let resolved = composition(state, family)

        #expect(resolved.headline == WidgetFormatting.approximateByteCount(bytes))
        #expect(resolved.headline == "\u{2248}" + WidgetFormatting.byteCount(bytes))
        #expect(resolved.headlineParts == WidgetHeadlineParts(accent: WidgetFormatting.approximateByteCount(bytes)))
    }

    /// The layout colours the two pieces differently; the flat headline VoiceOver reads
    /// has to be those same pieces and nothing else.
    @Test("the flat headline is the joined parts", arguments: families)
    func headlineIsJoinedParts(family: WidgetLayoutFamily) throws {
        let progress = WidgetSessionProgress(reviewedClusters: 18, totalClusters: 30, updatedAt: Self.scannedAt)
        for state in [
            WidgetDisplayState.hasSuggestions(bytes: 1_000, clusterCount: 24, scannedAt: nil, isStale: false),
            .libraryChanged(bytes: 1_000, scannedAt: nil),
            .resumeReview(progress: progress, isStale: false)
        ] {
            let resolved = composition(state, family)
            let parts = try #require(resolved.headlineParts)
            #expect(resolved.headline == parts.joined, "\(state)")
        }
    }

    /// The wordmark takes the header once there is a figure; only the states that have
    /// nothing but a sentence keep a glyph beside it.
    @Test("a figure displaces the header glyph; a sentence keeps it", arguments: families)
    func headerSymbolOnlyWithoutFigure(family: WidgetLayoutFamily) {
        let progress = WidgetSessionProgress(reviewedClusters: 18, totalClusters: 30, updatedAt: Self.scannedAt)
        for state in [
            WidgetDisplayState.hasSuggestions(bytes: 1_000, clusterCount: 24, scannedAt: nil, isStale: false),
            .libraryChanged(bytes: 1_000, scannedAt: nil),
            .resumeReview(progress: progress, isStale: false)
        ] {
            #expect(composition(state, family).headerSymbolName == nil, "\(state) kept a glyph beside the figure")
        }
        for state in [
            WidgetDisplayState.unavailable, .noAccess(.denied), .neverScanned, .allCaughtUp(scannedAt: nil),
            .hasSuggestions(bytes: nil, clusterCount: nil, scannedAt: nil, isStale: false)
        ] {
            #expect(composition(state, family).headerSymbolName == composition(state, family).symbolName, "\(state) lost its glyph")
        }
    }

    /// `nil` in the snapshot means unknown, and unknown is not zero. A "0 bytes"
    /// headline would read as a measured result.
    @Test("an unknown byte count shows no headline rather than a fabricated zero", arguments: families)
    func unknownBytesShowNoHeadline(family: WidgetLayoutFamily) {
        let state = WidgetDisplayState.hasSuggestions(
            bytes: nil, clusterCount: nil, scannedAt: nil, isStale: false
        )

        #expect(composition(state, family).headline == nil)
        #expect(composition(state, family).detail == nil)
        #expect(composition(state, family).footnote == nil)
    }

    @Test("states with nothing measured carry no headline", arguments: families)
    func statesWithoutFigures(family: WidgetLayoutFamily) {
        for state in [
            WidgetDisplayState.unavailable,
            .noAccess(.denied),
            .neverScanned,
            .allCaughtUp(scannedAt: Self.scannedAt)
        ] {
            #expect(composition(state, family).headline == nil, "\(state) invented a headline")
            #expect(composition(state, family).progress == nil, "\(state) invented progress")
        }
    }

    // MARK: - Staleness

    /// The threshold is `WidgetPresentation.staleAfter`, computed once in
    /// `displayState`; the composition only obeys the flag it is handed. A figure shown
    /// without a date reads as today's.
    @Test("a stale reading carries the scan date", arguments: families)
    func staleCarriesTheDate(family: WidgetLayoutFamily) throws {
        let state = WidgetDisplayState.hasSuggestions(
            bytes: 1_000, clusterCount: 24, scannedAt: Self.scannedAt, isStale: true
        )
        let footnote = try #require(composition(state, family).footnote)
        let expectedDate = WidgetFormatting.timestamp(Self.scannedAt, timeStyle: .omitted)

        #expect(footnote.contains(expectedDate))
    }

    /// The count is medium's line, with the glyph the concept gives it. Small carries
    /// the figure, what it is, and the way in; a second number beside the first is what
    /// makes a small widget unreadable. A fresh figure has no footnote on either.
    @Test("a fresh medium lists the group count; a fresh small shows the action instead")
    func freshDetailPerFamily() throws {
        let state = WidgetDisplayState.hasSuggestions(
            bytes: 1_000, clusterCount: 24, scannedAt: Self.scannedAt, isStale: false
        )

        let medium = try #require(composition(state, .medium).detail)
        #expect(medium == WidgetDetailLine(symbolName: "photo.stack", text: WidgetL10n.Status.similarGroups(24)))
        #expect(composition(state, .medium).footnote == nil)
        #expect(composition(state, .medium).accessibilityLabel.contains(medium.text))

        #expect(composition(state, .small).detail == nil)
        #expect(composition(state, .small).footnote == nil)
        #expect(composition(state, .small).actionTitle != nil)
    }

    /// Every state a user can act on has to name where a tap goes; the states that can
    /// only say "open the app" have nothing to offer beyond the caption.
    @Test("actionable states carry an action title, dead ends do not", arguments: families)
    func actionTitles(family: WidgetLayoutFamily) {
        let progress = WidgetSessionProgress(reviewedClusters: 18, totalClusters: 30, updatedAt: Self.scannedAt)

        #expect(composition(.hasSuggestions(bytes: 1, clusterCount: 1, scannedAt: nil, isStale: false), family).actionTitle != nil)
        #expect(composition(.libraryChanged(bytes: 1, scannedAt: nil), family).actionTitle != nil)
        #expect(composition(.neverScanned, family).actionTitle != nil)
        #expect(composition(.resumeReview(progress: progress, isStale: false), family).actionTitle != nil)

        #expect(composition(.unavailable, family).actionTitle == nil)
        #expect(composition(.noAccess(.denied), family).actionTitle == nil)
    }

    /// A library that changed since the scan makes its figures historical whatever the
    /// staleness clock says, so the date travels with them regardless.
    @Test("a changed library dates its figures even when they are not yet stale", arguments: families)
    func libraryChangedIsDated(family: WidgetLayoutFamily) throws {
        let state = WidgetDisplayState.libraryChanged(bytes: 1_000, scannedAt: Self.scannedAt)
        let footnote = try #require(composition(state, family).footnote)

        #expect(footnote.contains(WidgetFormatting.timestamp(Self.scannedAt, timeStyle: .omitted)))
    }

    // MARK: - Progress

    @Test("progress is reviewed groups over total groups", arguments: families)
    func progressIsGroups(family: WidgetLayoutFamily) throws {
        let progress = WidgetSessionProgress(reviewedClusters: 18, totalClusters: 30, updatedAt: Self.scannedAt)
        let resolved = composition(.resumeReview(progress: progress, isStale: false), family)

        #expect(try #require(resolved.progress) == 0.6)
        let parts = try #require(resolved.headlineParts)
        #expect(parts.accent == WidgetFormatting.number(18))
        #expect(parts.rest == (family == .medium ? WidgetL10n.Status.ofGroups(30) : WidgetL10n.Status.ofTotal(30)))
        let rest = try #require(parts.rest)
        #expect(resolved.headline == "18 \(rest)")
    }

    /// A session that has not been sized yet has no fraction — not a zero one. A 0 %
    /// bar reads as "nothing reviewed", which is a different claim from "not known".
    @Test("a session with no groups yet draws no bar and no fraction", arguments: families)
    func emptySessionHasNoProgress(family: WidgetLayoutFamily) {
        let progress = WidgetSessionProgress(reviewedClusters: 0, totalClusters: 0, updatedAt: Self.scannedAt)
        let resolved = composition(.resumeReview(progress: progress, isStale: false), family)

        #expect(resolved.progress == nil)
        #expect(resolved.headline == nil)
        #expect(resolved.footnote == nil)
    }

    /// The concept's second line on medium is the groups left, not a caption that
    /// repeats the action; small names what the figure counts, because its total is
    /// already in the headline.
    @Test("medium captions the groups left to review; small keeps the bar and the way in")
    func remainingGroups() throws {
        let progress = WidgetSessionProgress(reviewedClusters: 18, totalClusters: 30, updatedAt: Self.scannedAt)
        let state = WidgetDisplayState.resumeReview(progress: progress, isStale: false)

        #expect(composition(state, .medium).caption == WidgetL10n.Status.groupsRemaining(12))
        #expect(composition(state, .medium).footnote == nil)
        #expect(composition(state, .small).caption == WidgetL10n.Status.groupsReviewed)
        #expect(composition(state, .small).footnote == nil)
        #expect(composition(state, .small).progress != nil)
    }

    @Test("a stale session shows when it was last touched instead of what is left", arguments: families)
    func staleSessionIsDated(family: WidgetLayoutFamily) throws {
        let progress = WidgetSessionProgress(reviewedClusters: 18, totalClusters: 30, updatedAt: Self.reviewedAt)
        let footnote = try #require(composition(.resumeReview(progress: progress, isStale: true), family).footnote)

        #expect(footnote.contains(WidgetFormatting.timestamp(Self.reviewedAt, timeStyle: .omitted)))
    }

    /// A scan on the 1st, a review resumed on the 3rd, then the app left shut: the
    /// session date is the only one the resume state carries, so it has to be worded as
    /// a review. Dating it "Scanned" reported a scan that never happened on that day —
    /// on screen and, because the footnote is part of the label, to VoiceOver too.
    @Test("the stale session date is worded as a review, not as a scan", arguments: families)
    func staleSessionIsNotDatedAsAScan(family: WidgetLayoutFamily) throws {
        let progress = WidgetSessionProgress(reviewedClusters: 18, totalClusters: 30, updatedAt: Self.reviewedAt)
        let snapshot = WidgetSnapshot(
            generatedAt: Self.reviewedAt,
            photoAuthorization: .authorized,
            hasCompletedScan: true,
            lastScanDate: Self.scannedAt,
            estimatedSavingsBytes: 1_932_735_283,
            clusterCount: 24,
            sessionProgress: progress
        )
        let state = WidgetPresentation.displayState(
            for: snapshot,
            now: Self.reviewedAt.addingTimeInterval(WidgetPresentation.staleAfter)
        )
        let resolved = composition(state, family)
        let footnote = try #require(resolved.footnote)

        #expect(footnote == WidgetL10n.Status.lastReviewed(
            WidgetFormatting.timestamp(Self.reviewedAt, timeStyle: .omitted)
        ))
        #expect(footnote != WidgetL10n.Status.lastScanned(
            WidgetFormatting.timestamp(Self.reviewedAt, timeStyle: .omitted)
        ))
        #expect(!footnote.contains(WidgetFormatting.timestamp(Self.scannedAt, timeStyle: .omitted)))
        #expect(resolved.accessibilityLabel.contains(footnote))
    }

    // MARK: - Hero

    @Test("each state picks the scene that matches what it says", arguments: families)
    func heroPerState(family: WidgetLayoutFamily) {
        let progress = WidgetSessionProgress(reviewedClusters: 1, totalClusters: 4, updatedAt: Self.scannedAt)

        #expect(composition(.hasSuggestions(bytes: 1, clusterCount: 1, scannedAt: nil, isStale: false), family).hero == .hasReviews)
        #expect(composition(.libraryChanged(bytes: 1, scannedAt: nil), family).hero == .hasReviews)
        #expect(composition(.allCaughtUp(scannedAt: nil), family).hero == .allCaughtUp)
        #expect(composition(.resumeReview(progress: progress, isStale: false), family).hero == .comparisonReview)
    }

    /// Nothing has been measured, so there is nothing to illustrate; the small layout
    /// gives the space to the sentence instead.
    @Test("states with no data show no hero on the small layout")
    func noHeroWhenNothingToShow() {
        for state in [WidgetDisplayState.unavailable, .noAccess(.denied), .neverScanned] {
            #expect(composition(state, .small).hero == nil, "\(state) drew a hero on small")
        }
        #expect(composition(.unavailable, .medium).hero == nil)
        #expect(composition(.noAccess(.limited), .medium).hero == nil)
    }

    /// Every scene a composition can name has to be a scene that is actually bundled,
    /// or the widget renders a hole. `WidgetHeroAssetsTests` proves the files exist;
    /// this proves the compositions only ask for those.
    @Test("every hero a composition names is one the bundle carries", arguments: families)
    func heroesAreResolvable(family: WidgetLayoutFamily) {
        let progress = WidgetSessionProgress(reviewedClusters: 1, totalClusters: 4, updatedAt: Self.scannedAt)
        let states: [WidgetDisplayState] = [
            .unavailable, .noAccess(.limited), .noAccess(.denied), .neverScanned,
            .allCaughtUp(scannedAt: Self.scannedAt),
            .hasSuggestions(bytes: 1, clusterCount: 1, scannedAt: Self.scannedAt, isStale: false),
            .libraryChanged(bytes: 1, scannedAt: Self.scannedAt),
            .resumeReview(progress: progress, isStale: false)
        ]

        for state in states {
            guard let hero = composition(state, family).hero else { continue }
            #expect(WidgetHeroAssets.url(for: hero, scale: .twoX) != nil, "\(state) names an unbundled hero")
        }
    }

    // MARK: - Destination and accessibility

    /// The composition must not re-derive routing: two answers to "where does a tap go"
    /// is one answer too many.
    @Test("the destination is the one WidgetPresentation already decided", arguments: families)
    func destinationMatchesPresentation(family: WidgetLayoutFamily) {
        let progress = WidgetSessionProgress(reviewedClusters: 1, totalClusters: 4, updatedAt: Self.scannedAt)
        let states: [WidgetDisplayState] = [
            .unavailable, .noAccess(.denied), .neverScanned,
            .allCaughtUp(scannedAt: nil),
            .hasSuggestions(bytes: 1, clusterCount: 1, scannedAt: nil, isStale: false),
            .libraryChanged(bytes: 1, scannedAt: nil),
            .resumeReview(progress: progress, isStale: false)
        ]

        for state in states {
            #expect(composition(state, family).destination == WidgetPresentation.destination(for: state))
        }
        #expect(composition(.resumeReview(progress: progress, isStale: false), family).destination == .resumeReview)
    }

    /// The regression `46f405b` fixed for the one layout that existed then: without the
    /// footnote, VoiceOver reads a day-old figure as the current one.
    @Test("the accessibility label carries the footnote, so a stale figure is heard as stale", arguments: families)
    func labelIncludesFootnote(family: WidgetLayoutFamily) throws {
        let state = WidgetDisplayState.hasSuggestions(
            bytes: 1_000, clusterCount: 24, scannedAt: Self.scannedAt, isStale: true
        )
        let resolved = composition(state, family)
        let footnote = try #require(resolved.footnote)

        #expect(resolved.accessibilityLabel.contains(footnote))
    }

    @Test("the accessibility label carries the figure, the unit and the caption", arguments: families)
    func labelCarriesTheFigure(family: WidgetLayoutFamily) throws {
        let resolved = composition(
            .hasSuggestions(bytes: 1_932_735_283, clusterCount: 24, scannedAt: Self.scannedAt, isStale: false),
            family
        )

        #expect(resolved.accessibilityLabel.contains(try #require(resolved.headline)))
        #expect(resolved.accessibilityLabel.contains(resolved.caption))
    }

    @Test("no composition is left without something to read out", arguments: families)
    func everyStateSpeaks(family: WidgetLayoutFamily) {
        let progress = WidgetSessionProgress(reviewedClusters: 0, totalClusters: 0, updatedAt: Self.scannedAt)
        let states: [WidgetDisplayState] = [
            .unavailable, .noAccess(.limited), .noAccess(.denied), .noAccess(.notDetermined),
            .neverScanned, .allCaughtUp(scannedAt: nil),
            .hasSuggestions(bytes: nil, clusterCount: nil, scannedAt: nil, isStale: false),
            .libraryChanged(bytes: nil, scannedAt: nil),
            .resumeReview(progress: progress, isStale: false)
        ]

        for state in states {
            let resolved = composition(state, family)
            #expect(!resolved.caption.isEmpty, "\(state) has no caption")
            #expect(!resolved.accessibilityLabel.isEmpty, "\(state) has nothing to read out")
            #expect(!resolved.accessibilityHint.isEmpty, "\(state) has no hint")
            #expect(!resolved.symbolName.isEmpty, "\(state) has no symbol")
        }
    }

    /// A resume tap goes somewhere else than a cleanup tap, so it has to say something
    /// else before the user commits to it.
    @Test("resuming a review announces a different destination than cleanup", arguments: families)
    func resumeHintDiffers(family: WidgetLayoutFamily) {
        let progress = WidgetSessionProgress(reviewedClusters: 1, totalClusters: 4, updatedAt: Self.scannedAt)
        let resume = composition(.resumeReview(progress: progress, isStale: false), family)
        let cleanup = composition(.hasSuggestions(bytes: 1, clusterCount: 1, scannedAt: nil, isStale: false), family)

        #expect(resume.accessibilityHint != cleanup.accessibilityHint)
    }

    // MARK: - Family differences

    /// Medium is not a bigger small. If the two ever resolve identically for the states
    /// that carry data, one of the layouts has stopped earning its size.
    @Test("medium says more than small where it has the room")
    func mediumDiffersFromSmall() {
        let suggestions = WidgetDisplayState.hasSuggestions(
            bytes: 1_000, clusterCount: 24, scannedAt: Self.scannedAt, isStale: false
        )
        #expect(composition(suggestions, .medium).detail != nil)
        #expect(composition(suggestions, .small).detail == nil)

        let progress = WidgetSessionProgress(reviewedClusters: 18, totalClusters: 30, updatedAt: Self.scannedAt)
        let resume = WidgetDisplayState.resumeReview(progress: progress, isStale: false)
        #expect(composition(resume, .medium).caption != composition(resume, .small).caption)
    }

    /// Medium has room for both the count and the date, on two lines; small has to
    /// choose, and chooses the date, because an undated figure claims to be current.
    @Test("a stale medium keeps the count line and dates it; a stale small keeps the date")
    func staleFootnotesPerFamily() throws {
        let state = WidgetDisplayState.hasSuggestions(
            bytes: 1_000, clusterCount: 24, scannedAt: Self.scannedAt, isStale: true
        )
        let date = WidgetFormatting.timestamp(Self.scannedAt, timeStyle: .omitted)

        let small = composition(state, .small)
        #expect(try #require(small.footnote).contains(date))
        #expect(small.detail == nil)

        let medium = composition(state, .medium)
        #expect(medium.footnote == WidgetL10n.Status.lastScanned(date))
        #expect(try #require(medium.detail).text.contains("24"))
    }
}
