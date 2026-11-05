import Cleanup
import Core
import Foundation
import WidgetSupport
import Testing
@testable import Alike

/// `MainTabView` binds `TabManager.selectedTab` and tags each tab with its `TabManager.Tab`
/// value, so navigation and widget deep links land through `TabManager` alone. These tests
/// lock that routing; the views themselves are not rendered.
@MainActor
@Suite struct MainTabSelectionTests {
    @Test func testTabValuesKeepTheirOrder() {
        #expect(TabManager.Tab.allCases == [.scanner, .cleanup, .settings])
        #expect(TabManager().selectedTab == .scanner)
    }

    @Test func testNavigationActionsSelectTheExpectedTab() {
        let manager = TabManager()

        manager.navigateToCleanup()
        #expect(manager.selectedTab == .cleanup)
        #expect(manager.pendingCleanupEntry == nil)

        manager.navigateToScanner(andStartScan: true)
        #expect(manager.selectedTab == .scanner)
        #expect(manager.shouldStartScan)

        manager.selectedTab = .settings
        manager.requestRescan()
        manager.triggerRescan()
        #expect(manager.selectedTab == .scanner)
        #expect(!manager.needsRescan)
    }

    @Test func testResumeWidgetLinkLandsOnCleanupWithResumeEntry() throws {
        let url = try #require(URL(string: "alike://resume"))
        let destination = try #require(WidgetDestination(url: url))
        let manager = TabManager()

        manager.follow(destination)

        #expect(manager.selectedTab == .cleanup)
        #expect(manager.pendingCleanupEntry == .resumeReview)
        #expect(!manager.shouldStartScan)
    }

    @Test func testEveryWidgetDestinationLandsOnCleanupWithItsEntry() {
        let expected: [WidgetDestination: CleanupWidgetEntry?] = [
            .cleanup: nil,
            .resumeReview: .resumeReview,
            .similarPhotos: .similarPhotos,
            .screenshots: .category(.screenshots),
            .blurredPhotos: .category(.blurredPhotos)
        ]
        #expect(Set(expected.keys) == Set(WidgetDestination.allCases))

        for destination in WidgetDestination.allCases {
            let manager = TabManager()
            manager.follow(destination)
            #expect(manager.selectedTab == .cleanup, "\(destination)")
            #expect(manager.pendingCleanupEntry == expected[destination] ?? nil, "\(destination)")
        }
    }
}
