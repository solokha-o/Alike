import Foundation
import Testing
@testable import WidgetSupport

/// The Lock Screen's three shapes, resolved from the same seven states the Home Screen
/// draws. What is decided here and nowhere else: which fact each slot shows, whether a
/// ring is drawn, that the rectangular slot always names an action, and that nothing
/// ever asks for a hero the monochrome renderer cannot draw.
@Suite("Widget accessory composition")
struct WidgetAccessoryCompositionTests {
    private static let scannedAt = Date(timeIntervalSince1970: 1_757_000_000)
    private static let families = WidgetLayoutFamily.accessory
    private static let bytes: Int64 = 1_932_735_283
    private static let libraryBytes: Int64 = 27_917_287_424

    private static let progress = WidgetSessionProgress(reviewedClusters: 18, totalClusters: 30, updatedAt: scannedAt)

    private static let everyState: [WidgetDisplayState] = [
        .unavailable, .noAccess(.limited), .noAccess(.denied), .neverScanned,
        .allCaughtUp(scannedAt: scannedAt),
        .hasSuggestions(bytes: bytes, clusterCount: 24, scannedAt: scannedAt, isStale: false),
        .hasSuggestions(bytes: bytes, clusterCount: 24, scannedAt: scannedAt, isStale: true),
        .libraryChanged(bytes: bytes, scannedAt: scannedAt),
        .resumeReview(progress: progress, isStale: false),
        .resumeReview(progress: progress, isStale: true)
    ]

    private func composition(
        _ state: WidgetDisplayState,
        _ family: WidgetLayoutFamily,
        libraryTotalBytes: Int64? = nil
    ) -> WidgetComposition {
        WidgetPresentation.composition(for: state, family: family, libraryTotalBytes: libraryTotalBytes)
    }

    // MARK: - Families

    @Test("the accessory families are the three Lock Screen slots and nothing on the Home Screen")
    func familiesArePartitioned() {
        #expect(Set(WidgetLayoutFamily.allCases) == Set(WidgetLayoutFamily.homeScreen + WidgetLayoutFamily.accessory))
        #expect(WidgetLayoutFamily.homeScreen.allSatisfy { !$0.isAccessory })
        #expect(WidgetLayoutFamily.accessory.allSatisfy { $0.isAccessory })
    }

    @Test("the Home Screen compositions do not change when the family argument is omitted", arguments: WidgetLayoutFamily.homeScreen)
    func homeScreenIgnoresLibraryBytes(family: WidgetLayoutFamily) {
        for state in Self.everyState {
            let without = WidgetPresentation.composition(for: state, family: family)
            let with = composition(state, family, libraryTotalBytes: Self.libraryBytes)
            #expect(without == with, "\(state) on \(family) changed with a library size")
        }
    }

    // MARK: - Shared

    @Test("no state on any accessory family asks for a hero", arguments: families)
    func neverAHero(family: WidgetLayoutFamily) {
        for state in Self.everyState {
            #expect(composition(state, family).hero == nil, "\(state) drew a hero on \(family)")
        }
    }

    @Test("every state has a brand or state glyph in the header", arguments: families)
    func alwaysAGlyph(family: WidgetLayoutFamily) {
        for state in Self.everyState {
            #expect(composition(state, family).headerSymbolName != nil, "\(state) has no glyph on \(family)")
        }
    }

    @Test("the priority between facts is the display state's, unchanged", arguments: families)
    func priorityIsTheState(family: WidgetLayoutFamily) {
        // A snapshot that could show all three facts shows the review, exactly as the
        // Home Screen does, because `displayState` decides once for every family.
        let snapshot = WidgetSnapshot(
            generatedAt: Self.scannedAt,
            photoAuthorization: .authorized,
            hasCompletedScan: true,
            lastScanDate: Self.scannedAt,
            libraryChangedSinceScan: true,
            estimatedSavingsBytes: Self.bytes,
            libraryTotalBytes: Self.libraryBytes,
            clusterCount: 24,
            sessionProgress: Self.progress
        )
        let state = WidgetPresentation.displayState(for: snapshot, now: Self.scannedAt)
        let resolved = composition(state, family, libraryTotalBytes: snapshot.libraryTotalBytes)
        #expect(resolved.destination == .resumeReview)
        #expect(resolved.accessibilityHint == WidgetL10n.Accessibility.resumeReview)
    }

    @Test("a tap goes where the presentation says, never somewhere the slot decided", arguments: families)
    func destinationMatchesPresentation(family: WidgetLayoutFamily) {
        for state in Self.everyState {
            #expect(composition(state, family).destination == WidgetPresentation.destination(for: state))
        }
    }

    @Test("every state speaks to VoiceOver", arguments: families)
    func everyStateSpeaks(family: WidgetLayoutFamily) {
        for state in Self.everyState {
            let resolved = composition(state, family)
            #expect(!resolved.accessibilityLabel.isEmpty, "\(state) is silent on \(family)")
            #expect(!resolved.accessibilityHint.isEmpty)
        }
    }

    // MARK: - Inline

    @Test("inline is one line and nothing else")
    func inlineIsOneLine() {
        for state in Self.everyState {
            let resolved = composition(state, .accessoryInline)
            #expect(resolved.headline == nil, "\(state) set a headline inline")
            #expect(resolved.headlineParts == nil)
            #expect(resolved.actionTitle == nil, "\(state) set an action inline")
            #expect(resolved.footnote == nil)
            #expect(resolved.detail == nil)
            #expect(resolved.progress == nil)
            #expect(!resolved.caption.isEmpty)
            #expect(resolved.accessibilityLabel == resolved.caption)
        }
    }

    @Test("inline names each fact with its short key")
    func inlineFacts() {
        let approx = WidgetFormatting.approximateByteCount(Self.bytes)
        #expect(composition(.hasSuggestions(bytes: Self.bytes, clusterCount: 24, scannedAt: nil, isStale: false), .accessoryInline).caption
            == WidgetL10n.Accessory.reclaimable(approx))
        #expect(composition(.libraryChanged(bytes: Self.bytes, scannedAt: nil), .accessoryInline).caption
            == WidgetL10n.Accessory.reclaimable(approx))
        #expect(composition(.resumeReview(progress: Self.progress, isStale: false), .accessoryInline).caption
            == WidgetL10n.Accessory.review(18, 30))
        #expect(composition(.allCaughtUp(scannedAt: nil), .accessoryInline).caption == WidgetL10n.Accessory.allCaughtUp)
        #expect(composition(.unavailable, .accessoryInline).caption == WidgetL10n.Status.openApp)
        #expect(composition(.noAccess(.denied), .accessoryInline).caption == WidgetL10n.Status.openApp)
        #expect(composition(.neverScanned, .accessoryInline).caption == WidgetL10n.Action.scan)
    }

    @Test("inline falls back to the action when the figure is unknown")
    func inlineWithoutFigure() {
        #expect(composition(.hasSuggestions(bytes: nil, clusterCount: nil, scannedAt: nil, isStale: false), .accessoryInline).caption
            == WidgetL10n.Action.review)
        let unsized = WidgetSessionProgress(reviewedClusters: 0, totalClusters: 0, updatedAt: Self.scannedAt)
        #expect(composition(.resumeReview(progress: unsized, isStale: false), .accessoryInline).caption
            == WidgetL10n.Action.continueReview)
    }

    // MARK: - Rectangular

    @Test("rectangular always carries the title and an action")
    func rectangularAlwaysActs() {
        for state in Self.everyState {
            let resolved = composition(state, .accessoryRectangular)
            #expect(resolved.caption == WidgetL10n.Accessory.title, "\(state) lost the title")
            #expect(resolved.actionTitle != nil, "\(state) has no action on rectangular")
            #expect(resolved.actionStyle == .plain)
        }
    }

    @Test("rectangular actions name the destination")
    func rectangularActions() {
        #expect(composition(.hasSuggestions(bytes: Self.bytes, clusterCount: 24, scannedAt: nil, isStale: false), .accessoryRectangular).actionTitle == WidgetL10n.Action.review)
        #expect(composition(.libraryChanged(bytes: Self.bytes, scannedAt: nil), .accessoryRectangular).actionTitle == WidgetL10n.Action.review)
        #expect(composition(.resumeReview(progress: Self.progress, isStale: false), .accessoryRectangular).actionTitle == WidgetL10n.Action.continueReview)
        #expect(composition(.neverScanned, .accessoryRectangular).actionTitle == WidgetL10n.Action.scan)
        #expect(composition(.allCaughtUp(scannedAt: nil), .accessoryRectangular).actionTitle == WidgetL10n.Status.openApp)
        #expect(composition(.unavailable, .accessoryRectangular).actionTitle == WidgetL10n.Status.openApp)
    }

    @Test("rectangular shows the figure with its sign, and the review as «18 of 30»")
    func rectangularFigures() throws {
        let bytes = composition(.hasSuggestions(bytes: Self.bytes, clusterCount: 24, scannedAt: nil, isStale: false), .accessoryRectangular)
        #expect(bytes.headline == WidgetFormatting.approximateByteCount(Self.bytes))

        let review = try #require(composition(.resumeReview(progress: Self.progress, isStale: false), .accessoryRectangular).headlineParts)
        #expect(review.accent == WidgetFormatting.number(18))
        #expect(review.rest == WidgetL10n.Status.ofTotal(30))
    }

    @Test("rectangular dates only a stale estimate and «all caught up»")
    func rectangularDates() throws {
        let stamp = WidgetFormatting.timestamp(Self.scannedAt, timeStyle: .omitted)
        let stale = composition(.hasSuggestions(bytes: Self.bytes, clusterCount: 24, scannedAt: Self.scannedAt, isStale: true), .accessoryRectangular)
        #expect(try #require(stale.footnote).contains(stamp))
        #expect(stale.accessibilityLabel.contains(stamp))

        let caughtUp = composition(.allCaughtUp(scannedAt: Self.scannedAt), .accessoryRectangular)
        #expect(try #require(caughtUp.footnote).contains(stamp))

        #expect(composition(.hasSuggestions(bytes: Self.bytes, clusterCount: 24, scannedAt: Self.scannedAt, isStale: false), .accessoryRectangular).footnote == nil)
        #expect(composition(.libraryChanged(bytes: Self.bytes, scannedAt: Self.scannedAt), .accessoryRectangular).footnote == nil)
        #expect(composition(.resumeReview(progress: Self.progress, isStale: true), .accessoryRectangular).footnote == nil)
    }

    @Test("rectangular shows «all caught up» on screen, dated or not", arguments: [scannedAt, nil] as [Date?])
    func rectangularAllCaughtUpIsVisible(scannedAt: Date?) {
        let resolved = composition(.allCaughtUp(scannedAt: scannedAt), .accessoryRectangular)
        #expect(resolved.headline == WidgetL10n.Accessory.allCaughtUp)
        #expect(resolved.headlineParts?.accent == WidgetL10n.Accessory.allCaughtUp)
        #expect(resolved.caption == WidgetL10n.Accessory.title)
        #expect(resolved.actionTitle == WidgetL10n.Status.openApp)
        #expect((resolved.footnote != nil) == (scannedAt != nil))
        #expect(resolved.accessibilityLabel.components(separatedBy: WidgetL10n.Accessory.allCaughtUp).count == 2)
    }

    @Test("rectangular does not repeat the action as a headline")
    func rectangularNoEchoedAction() {
        #expect(composition(.neverScanned, .accessoryRectangular).headline == nil)
        #expect(composition(.unavailable, .accessoryRectangular).headline == nil)
        #expect(composition(.hasSuggestions(bytes: nil, clusterCount: nil, scannedAt: nil, isStale: false), .accessoryRectangular).headline == nil)
    }

    @Test("rectangular reads the fact to VoiceOver, not the app name twice")
    func rectangularLabel() {
        let resolved = composition(.hasSuggestions(bytes: Self.bytes, clusterCount: 24, scannedAt: nil, isStale: false), .accessoryRectangular)
        #expect(resolved.accessibilityLabel.contains(WidgetFormatting.approximateByteCount(Self.bytes)))
        #expect(!resolved.accessibilityLabel.contains(WidgetL10n.Accessory.title))
    }

    // MARK: - Circular

    @Test("circular draws the reclaimable share only when the library size is known")
    func circularShare() throws {
        let state = WidgetDisplayState.hasSuggestions(bytes: Self.bytes, clusterCount: 24, scannedAt: nil, isStale: false)

        #expect(composition(state, .accessoryCircular).progress == nil)
        #expect(composition(state, .accessoryCircular, libraryTotalBytes: 0).progress == nil)

        let share = try #require(composition(state, .accessoryCircular, libraryTotalBytes: Self.libraryBytes).progress)
        #expect(abs(share - Double(Self.bytes) / Double(Self.libraryBytes)) < 0.000_001)

        #expect(composition(.libraryChanged(bytes: Self.bytes, scannedAt: nil), .accessoryCircular, libraryTotalBytes: Self.libraryBytes).progress == share)
        #expect(composition(.libraryChanged(bytes: nil, scannedAt: nil), .accessoryCircular, libraryTotalBytes: Self.libraryBytes).progress == nil)
    }

    @Test("a share is clamped when the estimate outgrows the library it was measured against")
    func circularShareIsClamped() {
        let state = WidgetDisplayState.hasSuggestions(bytes: Self.libraryBytes * 2, clusterCount: 24, scannedAt: nil, isStale: false)
        #expect(composition(state, .accessoryCircular, libraryTotalBytes: Self.libraryBytes).progress == 1)
    }

    @Test("circular draws the review as reviewed over total, and no ring for an unsized session")
    func circularReview() throws {
        let sized = composition(.resumeReview(progress: Self.progress, isStale: false), .accessoryCircular)
        #expect(sized.progress == Self.progress.fraction)
        let parts = try #require(sized.headlineParts)
        #expect(parts.accent == WidgetFormatting.number(18))
        #expect(parts.rest == "/" + WidgetFormatting.number(30))

        let unsized = WidgetSessionProgress(reviewedClusters: 0, totalClusters: 0, updatedAt: Self.scannedAt)
        let resolved = composition(.resumeReview(progress: unsized, isStale: false), .accessoryCircular)
        #expect(resolved.progress == nil)
        #expect(resolved.headline == nil)
    }

    @Test("circular shows the bare figure under the brand glyph, without the «≈»")
    func circularFigure() {
        let resolved = composition(.hasSuggestions(bytes: Self.bytes, clusterCount: 24, scannedAt: nil, isStale: false), .accessoryCircular)
        #expect(resolved.headline == WidgetFormatting.byteCount(Self.bytes))
        #expect(resolved.headerSymbolName == "photo.stack")
        #expect(resolved.actionTitle == nil)
        #expect(resolved.footnote == nil)
    }

    @Test("«all caught up» swaps the figure for a tick and keeps no ring")
    func circularCaughtUp() {
        let resolved = composition(.allCaughtUp(scannedAt: Self.scannedAt), .accessoryCircular)
        #expect(resolved.headerSymbolName == "checkmark")
        #expect(resolved.headline == nil)
        #expect(resolved.progress == nil)
        #expect(composition(.allCaughtUp(scannedAt: Self.scannedAt), .accessoryRectangular).headerSymbolName == "photo.stack")
    }

    @Test("states without a figure draw no ring and no number", arguments: families)
    func noFigureNoRing(family: WidgetLayoutFamily) {
        for state in [WidgetDisplayState.unavailable, .noAccess(.denied), .noAccess(.limited), .neverScanned] {
            let resolved = composition(state, family, libraryTotalBytes: Self.libraryBytes)
            #expect(resolved.progress == nil, "\(state) drew a ring on \(family)")
            #expect(resolved.headline == nil, "\(state) drew a figure on \(family)")
        }
    }
}
