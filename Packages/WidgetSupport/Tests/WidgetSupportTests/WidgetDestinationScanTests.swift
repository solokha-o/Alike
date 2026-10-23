import XCTest
@testable import WidgetSupport

/// The `.scan` destination added for App Intents (spike #5). Kept in its own XCTest
/// file: the neighbouring `WidgetDestinationTests` use Swift Testing and are left as
/// they are.
final class WidgetDestinationScanTests: XCTestCase {
    func testScanUsesTheSharedSchemeAndItsOwnHost() {
        XCTAssertEqual(WidgetDestination.scan.host, "scan")
        XCTAssertEqual(WidgetDestination.scan.url.absoluteString, "alike://scan")
    }

    func testScanRoundTripsThroughURLParsing() throws {
        let url = try XCTUnwrap(URL(string: "alike://scan"))
        XCTAssertEqual(WidgetDestination(url: url), .scan)
        XCTAssertEqual(WidgetDestination(url: try XCTUnwrap(URL(string: "alike:scan"))), .scan)
    }

    func testExistingHostsAreUnchanged() {
        // A renamed host would break links widgets already hold on a home screen.
        XCTAssertEqual(
            WidgetDestination.allCases.map(\.host),
            ["cleanup", "resume", "similar", "screenshots", "blurred", "scan"]
        )
    }
}
