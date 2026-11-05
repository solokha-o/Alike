import Foundation
import Testing
@testable import Purchases
import Core

/// `DebugPremiumAccessController` is scaffolding, but a leaky one would make
/// manual QA lie: a tester comparing "free" behaviour would silently be looking
/// at an unlocked build. So the override has to apply to exactly the feature
/// whose key is set, and to nothing else.
@MainActor
@Suite final class DebugPremiumAccessControllerTests {
    private let defaults: UserDefaults
    private let suiteName: String

    init() throws {
        suiteName = "DebugPremiumAccessControllerTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        // deinit is nonisolated: open the suite by name instead of reading `defaults`.
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    @Test func testOverrideUnlocksOnlyTheFeatureWhoseKeyIsSet() {
        for overridden in PremiumFeature.allCases {
            defaults.removePersistentDomain(forName: suiteName)
            defaults.set(true, forKey: overridden.debugOverrideDefaultsKey)
            let controller = DebugPremiumAccessController(
                base: PremiumAccessController(),
                defaults: defaults
            )

            #expect(controller.access(to: overridden) == .allowed)

            for other in PremiumFeature.allCases where other != overridden {
                #expect(
                    controller.access(to: other) == PremiumAccessController().access(to: other),
                    "overriding \(overridden) also changed \(other)"
                )
            }
        }
    }

    @Test func testWithoutOverridesEveryDecisionMatchesTheBaseController() {
        let base = PremiumAccessController()
        let controller = DebugPremiumAccessController(base: base, defaults: defaults)
        let contexts: [PremiumAccessContext] = [
            .none,
            .scan(completedThisMonth: 0),
            .scan(completedThisMonth: 99),
            .cleanupSelection(count: 1),
            .cleanupSelection(count: 50)
        ]

        for feature in PremiumFeature.allCases {
            for context in contexts {
                #expect(
                    controller.access(to: feature, context: context) == base.access(to: feature, context: context),
                    "\(feature) in \(context) diverges from the base controller"
                )
            }
        }
    }

    @Test func testOverrideBeatsTheContextThatWouldOtherwiseLockTheFeature() {
        defaults.set(true, forKey: PremiumFeature.unlimitedScans.debugOverrideDefaultsKey)
        let controller = DebugPremiumAccessController(
            base: PremiumAccessController(),
            defaults: defaults
        )

        #expect(
            controller.access(to: .unlimitedScans, context: .scan(completedThisMonth: 99)) == .allowed
        )
    }

    @Test func testEntitlementStateIsNotFakedByAnOverride() {
        // The override exists to reach gated screens, not to pretend a purchase
        // happened. Anything reading `entitlementState` — receipt-driven copy,
        // restore prompts — must still see the real, unpurchased state.
        defaults.set(true, forKey: PremiumFeature.batchCleanup.debugOverrideDefaultsKey)
        let controller = DebugPremiumAccessController(
            base: PremiumAccessController(),
            defaults: defaults
        )

        #expect(!controller.entitlementState.isPremium)
    }

    @Test func testEveryFeatureHasADistinctOverrideKey() {
        let keys = PremiumFeature.allCases.map(\.debugOverrideDefaultsKey)

        #expect(Set(keys).count == keys.count, "two features share a debug override key")
    }
}
