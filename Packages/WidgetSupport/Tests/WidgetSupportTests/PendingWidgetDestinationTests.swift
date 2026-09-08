import Foundation
import Testing
@testable import WidgetSupport

@Suite("Pending widget destination")
@MainActor
struct PendingWidgetDestinationTests {
    @Test("Nothing is pending before a link arrives")
    func startsEmpty() {
        #expect(PendingWidgetDestination().destination == nil)
    }

    @Test("A link is held rather than acted on, so a cold launch does not lose it")
    func holdsUntilConsumed() throws {
        let pending = PendingWidgetDestination()

        pending.handle(WidgetDestination.screenshots.url)

        // Still pending after the launch route and the permission check would have run.
        #expect(pending.destination == .screenshots)
        #expect(pending.consume() == .screenshots)
    }

    @Test("A link is followed once, not again on the next state change")
    func consumesOnce() {
        let pending = PendingWidgetDestination()
        pending.handle(WidgetDestination.cleanup.url)

        #expect(pending.consume() == .cleanup)
        #expect(pending.consume() == nil)
        #expect(pending.destination == nil)
    }

    @Test("A second link replaces the first instead of queueing behind it")
    func latestWins() {
        // Two taps before the app finishes launching: the one the user made last is
        // the one they are waiting to see.
        let pending = PendingWidgetDestination()

        pending.handle(WidgetDestination.cleanup.url)
        pending.handle(WidgetDestination.blurredPhotos.url)

        #expect(pending.consume() == .blurredPhotos)
    }

    @Test("An unrecognised URL leaves the pending destination alone")
    func unknownURLIsIgnored() throws {
        let pending = PendingWidgetDestination()
        pending.handle(WidgetDestination.cleanup.url)

        pending.handle(try #require(URL(string: "https://example.com/cleanup")))
        pending.handle(try #require(URL(string: "alike://unknown")))

        // Not cleared, and not replaced by a guess.
        #expect(pending.consume() == .cleanup)
    }
}
