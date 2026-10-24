import Cleanup
import Core
import WidgetSupport
import XCTest
@testable import Alike

/// `MainTabView` has 2 tab builders: the `Tab` API on iOS 27 (Scanner `.prominent`) and the
/// `.tabItem` path on iOS 17–26. Both bind the same `TabManager.selectedTab` and use the same
/// `TabManager.Tab` value per tab, so navigation and widget deep links must land on the same
/// tab on both. These tests lock the shared inputs; the views themselves are not rendered.
@MainActor
final class MainTabSelectionTests: XCTestCase {
    func testTabValuesAreTheSameForBothBuildersAndKeepTheirOrder() {
        XCTAssertEqual(TabManager.Tab.allCases, [.scanner, .cleanup, .settings])
        XCTAssertEqual(TabManager().selectedTab, .scanner)
    }

    func testOnlyScannerIsProminentOnIOS27() throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("TabRole.prominent needs iOS 27; the fallback has no tab role.")
        }
        XCTAssertEqual(TabManager.Tab.scanner.tabRole, .prominent)
        XCTAssertNil(TabManager.Tab.cleanup.tabRole)
        XCTAssertNil(TabManager.Tab.settings.tabRole)
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
