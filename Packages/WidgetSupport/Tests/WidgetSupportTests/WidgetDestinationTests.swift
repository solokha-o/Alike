import Foundation
import Testing
@testable import WidgetSupport

@Suite("Widget deep links")
struct WidgetDestinationTests {
    @Test("Every destination round-trips through its URL", arguments: WidgetDestination.allCases)
    func roundTrip(destination: WidgetDestination) throws {
        #expect(WidgetDestination(url: destination.url) == destination)
    }

    @Test("Hosts are the shipped contract and do not drift with the Swift case names")
    func hosts() {
        // A widget already on someone's home screen keeps issuing the URL it was
        // built with, so these strings are frozen once released.
        #expect(WidgetDestination.cleanup.url.absoluteString == "alike://cleanup")
        #expect(WidgetDestination.resumeReview.url.absoluteString == "alike://resume")
        #expect(WidgetDestination.similarPhotos.url.absoluteString == "alike://similar")
        #expect(WidgetDestination.screenshots.url.absoluteString == "alike://screenshots")
        #expect(WidgetDestination.blurredPhotos.url.absoluteString == "alike://blurred")
    }

    @Test("Hosts are unique, so no URL is ambiguous")
    func hostsAreUnique() {
        let hosts = WidgetDestination.allCases.map(\.host)
        #expect(Set(hosts).count == hosts.count)
    }

    @Test("A URL is matched case-insensitively")
    func caseInsensitive() throws {
        let url = try #require(URL(string: "ALIKE://Cleanup"))
        #expect(WidgetDestination(url: url) == .cleanup)
    }

    @Test("A trailing path cannot redirect a link away from its host")
    func trailingPathIsIgnored() throws {
        // The host is the destination; anything after it is not a second opinion.
        let url = try #require(URL(string: "alike://cleanup/../screenshots"))
        #expect(WidgetDestination(url: url) == .cleanup)
    }

    @Test("The path form is accepted alongside the host form")
    func pathForm() throws {
        // `alike:cleanup` has no authority component, so `url.host()` is nil.
        let url = try #require(URL(string: "alike:cleanup"))
        #expect(WidgetDestination(url: url) == .cleanup)
    }

    @Test(
        "Anything unrecognised is ignored rather than routed somewhere plausible",
        arguments: [
            "https://alike.app/cleanup",     // right host, wrong scheme
            "alike://",                      // no destination at all
            "alike://unknown",               // a destination this build does not have
            "alikey://cleanup",              // near-miss scheme
            "mailto:someone@example.com",
            "cleanup"
        ]
    )
    func rejected(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(WidgetDestination(url: url) == nil, "\(raw) should not resolve")
    }
}
