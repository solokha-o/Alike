import XCTest
@testable import Core

@MainActor
final class PremiumAccessTests: XCTestCase {
    func testFreeTierLocksUnconditionalPremiumFeatures() {
        let controller = PremiumAccessController()

        XCTAssertEqual(controller.access(to: .screenshotCleanup), .requiresPremium)
        XCTAssertEqual(controller.access(to: .blurredPhotoCleanup), .requiresPremium)
        XCTAssertEqual(controller.access(to: .advancedFilters), .requiresPremium)
        XCTAssertEqual(controller.access(to: .cleanupReminderCustomization), .requiresPremium)
    }

    func testFreeTierAllowsInitialScanAndFirstRescan() {
        let controller = PremiumAccessController()

        XCTAssertEqual(
            controller.access(to: .unlimitedRescans, context: .rescan(completedScanCount: 0)),
            .allowed
        )
        XCTAssertEqual(
            controller.access(to: .unlimitedRescans, context: .rescan(completedScanCount: 1)),
            .allowed
        )
        XCTAssertEqual(
            controller.access(to: .unlimitedRescans, context: .rescan(completedScanCount: 2)),
            .requiresPremium
        )
    }

    func testFreeTierAllowsOnlySinglePhotoCleanup() {
        let controller = PremiumAccessController()

        XCTAssertEqual(
            controller.access(to: .batchCleanup, context: .cleanupSelection(count: 1)),
            .allowed
        )
        XCTAssertEqual(
            controller.access(to: .batchCleanup, context: .cleanupSelection(count: 2)),
            .requiresPremium
        )
    }

    func testUnlockedFeatureOverridesFreePolicyWithoutUnlockingOtherFeatures() {
        let controller = PremiumAccessController(unlockedFeatures: [.advancedFilters])

        XCTAssertEqual(controller.access(to: .advancedFilters), .allowed)
        XCTAssertEqual(controller.access(to: .screenshotCleanup), .requiresPremium)
    }
}
