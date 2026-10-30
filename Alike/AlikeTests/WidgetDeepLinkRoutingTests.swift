import Cleanup
import Foundation
import WidgetSupport
import XCTest
@testable import Alike

/// Pins the full path from the URL a widget hands the app to the entry `CleanupView`
/// receives, for the two links that end on the cleanup screens: `alike://similar`
/// scrolls the cleanup root to its first group, and `alike://screenshots` opens the
/// screenshot sheet through the same Premium gate as an in-app tap.
///
/// `MainTabSelectionTests` covers each `WidgetDestination` case; these start from the
/// URL string itself, the value home-screen widgets already hold.
@MainActor
final class WidgetDeepLinkRoutingTests: XCTestCase {
    func testSimilarLinkLandsOnCleanupWithSimilarPhotosEntry() throws {
        let manager = try follow("alike://similar")

        XCTAssertEqual(manager.selectedTab, .cleanup)
        XCTAssertEqual(manager.pendingCleanupEntry, .similarPhotos)
        XCTAssertFalse(manager.shouldStartScan)
    }

    func testScreenshotsLinkLandsOnCleanupWithScreenshotsCategoryEntry() throws {
        let manager = try follow("alike://screenshots")

        XCTAssertEqual(manager.selectedTab, .cleanup)
        XCTAssertEqual(manager.pendingCleanupEntry, .category(.screenshots))
        XCTAssertFalse(manager.shouldStartScan)
    }

    func testSimilarAndScreenshotsHostsStayStable() {
        XCTAssertEqual(WidgetDestination.similarPhotos.url.absoluteString, "alike://similar")
        XCTAssertEqual(WidgetDestination.screenshots.url.absoluteString, "alike://screenshots")
    }

    private func follow(_ link: String) throws -> TabManager {
        let url = try XCTUnwrap(URL(string: link))
        let destination = try XCTUnwrap(WidgetDestination(url: url))
        let manager = TabManager()
        manager.follow(destination)
        return manager
    }
}
