import Foundation
import Testing
@testable import Core

@MainActor
@Suite struct PremiumAccessTests {
    @Test func testFreeTierLocksUnconditionalPremiumFeatures() {
        let controller = PremiumAccessController()

        #expect(controller.access(to: .screenshotCleanup) == .requiresPremium)
        #expect(controller.access(to: .blurredPhotoCleanup) == .requiresPremium)
        #expect(controller.access(to: .advancedFilters) == .requiresPremium)
        #expect(controller.access(to: .cleanupReminderCustomization) == .requiresPremium)
    }

    @Test func testFreeTierAllowsThreeMonthlyScansAndLocksFourth() {
        let controller = PremiumAccessController()

        #expect(
            controller.access(to: .unlimitedScans, context: .scan(completedThisMonth: 0)) == .allowed
        )
        #expect(
            controller.access(to: .unlimitedScans, context: .scan(completedThisMonth: 1)) == .allowed
        )
        #expect(
            controller.access(to: .unlimitedScans, context: .scan(completedThisMonth: 2)) == .allowed
        )
        #expect(
            controller.access(to: .unlimitedScans, context: .scan(completedThisMonth: 3)) == .requiresPremium
        )
    }

    @Test func testFreeTierAllowsOnlySinglePhotoCleanup() {
        let controller = PremiumAccessController()

        #expect(
            controller.access(to: .batchCleanup, context: .cleanupSelection(count: 1)) == .allowed
        )
        #expect(
            controller.access(to: .batchCleanup, context: .cleanupSelection(count: 2)) == .requiresPremium
        )
    }

    @Test func testUnlockedFeatureOverridesFreePolicyWithoutUnlockingOtherFeatures() {
        let controller = PremiumAccessController(unlockedFeatures: [.advancedFilters])

        #expect(controller.access(to: .advancedFilters) == .allowed)
        #expect(controller.access(to: .screenshotCleanup) == .requiresPremium)
    }
}
