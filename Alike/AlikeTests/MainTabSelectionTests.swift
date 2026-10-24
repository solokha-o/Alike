import Cleanup
import Core
import WidgetSupport
import XCTest
@testable import Alike

/// `MainTabView` binds `TabManager.selectedTab` and tags each tab with its `TabManager.Tab`
/// value, so navigation and widget deep links land through `TabManager` alone. These tests
/// lock that routing; the views themselves are not rendered.
@MainActor
final class MainTabSelectionTests: XCTestCase {
    func testTabValuesKeepTheirOrder() {
        XCTAssertEqual(TabManager.Tab.allCases, [.scanner, .cleanup, .settings])
        XCTAssertEqual(TabManager().selectedTab, .scanner)
    }

    func testNavigationActionsSelectTheExpectedTab() {
        let manager = TabManager()

        manager.navigateToCleanup()
        XCTAssertEqual(manager.selectedTab, .cleanup)
        XCTAssertNil(manager.pendingCleanupEntry)

        manager.navigateToScanner(andStartScan: true)
        XCTAssertEqual(manager.selectedTab, .scanner)
        XCTAssertTrue(manager.shouldStartScan)

        manager.selectedTab = .settings
        manager.requestRescan()
        manager.triggerRescan()
        XCTAssertEqual(manager.selectedTab, .scanner)
        XCTAssertFalse(manager.needsRescan)
    }

    func testResumeWidgetLinkLandsOnCleanupWithResumeEntry() throws {
        let destination = try XCTUnwrap(WidgetDestination(url: XCTUnwrap(URL(string: "alike://resume"))))
        let manager = TabManager()

        manager.follow(destination)

        XCTAssertEqual(manager.selectedTab, .cleanup)
        XCTAssertEqual(manager.pendingCleanupEntry, .resumeReview)
        XCTAssertFalse(manager.shouldStartScan)
    }

    func testEveryWidgetDestinationLandsOnCleanupWithItsEntry() {
        let expected: [WidgetDestination: CleanupWidgetEntry?] = [
            .cleanup: nil,
            .resumeReview: .resumeReview,
            .similarPhotos: .similarPhotos,
            .screenshots: .category(.screenshots),
            .blurredPhotos: .category(.blurredPhotos)
        ]
        XCTAssertEqual(Set(expected.keys), Set(WidgetDestination.allCases))

        for destination in WidgetDestination.allCases {
            let manager = TabManager()
            manager.follow(destination)
            XCTAssertEqual(manager.selectedTab, .cleanup, "\(destination)")
            XCTAssertEqual(manager.pendingCleanupEntry, expected[destination] ?? nil, "\(destination)")
        }
    }
}
