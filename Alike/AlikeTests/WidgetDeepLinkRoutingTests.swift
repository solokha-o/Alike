import Cleanup
import Foundation
import Testing
import WidgetSupport
@testable import Alike

/// Pins the full path from the URL a widget hands the app to the entry `CleanupView`
/// receives, for the two links that end on the cleanup screens: `alike://similar`
/// scrolls the cleanup root to its first group, and `alike://screenshots` opens the
/// screenshot sheet through the same Premium gate as an in-app tap.
///
/// `MainTabSelectionTests` covers each `WidgetDestination` case; these start from the
/// URL string itself, the value home-screen widgets already hold.
@MainActor
struct WidgetDeepLinkRoutingTests {
    @Test func testSimilarLinkLandsOnCleanupWithSimilarPhotosEntry() throws {
        let manager = try follow("alike://similar")

        #expect(manager.selectedTab == .cleanup)
        #expect(manager.pendingCleanupEntry == .similarPhotos)
        #expect(!manager.shouldStartScan)
    }

    @Test func testScreenshotsLinkLandsOnCleanupWithScreenshotsCategoryEntry() throws {
        let manager = try follow("alike://screenshots")

        #expect(manager.selectedTab == .cleanup)
        #expect(manager.pendingCleanupEntry == .category(.screenshots))
        #expect(!manager.shouldStartScan)
    }

    @Test func testSimilarAndScreenshotsHostsStayStable() {
        #expect(WidgetDestination.similarPhotos.url.absoluteString == "alike://similar")
        #expect(WidgetDestination.screenshots.url.absoluteString == "alike://screenshots")
    }

    private func follow(_ link: String) throws -> TabManager {
        let url = try #require(URL(string: link))
        let destination = try #require(WidgetDestination(url: url))
        let manager = TabManager()
        manager.follow(destination)
        return manager
    }
}
