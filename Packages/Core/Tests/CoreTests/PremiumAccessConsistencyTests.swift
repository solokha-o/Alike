import Foundation
import Testing
@testable import Core

/// Gating has to mean the same thing everywhere. Scanner, cluster Details and
/// Settings each ask about a feature with the context they happen to have, and
/// a feature that is open on one screen but locked on another is the failure
/// mode this suite exists to prevent.
///
/// `PremiumAccessTests` covers the free-tier boundaries themselves; these cover
/// that the boundaries do not move depending on who is asking.
@MainActor
@Suite struct PremiumAccessConsistencyTests {
    /// Contexts a caller might pass, including the mismatched ones. A screen
    /// that reuses whatever context it already has must not accidentally unlock
    /// an unrelated feature.
    private let contexts: [PremiumAccessContext] = [
        .none,
        .scan(completedThisMonth: 0),
        .scan(completedThisMonth: 99),
        .cleanupSelection(count: 1),
        .cleanupSelection(count: 50)
    ]

    @Test func testPremiumUnlocksEveryFeatureInEveryContext() {
        for feature in PremiumFeature.allCases {
            for context in contexts {
                #expect(
                    PremiumAccessPolicy.decision(for: feature, context: context, isPremium: true) == .allowed,
                    "\(feature) should be allowed for a premium user in \(context)"
                )
            }
        }
    }

    @Test func testFreeTierIgnoresContextsThatDoNotBelongToTheFeature() {
        for feature in PremiumFeature.allCases {
            for context in contexts {
                let isMatchingScan: Bool
                if case .scan = context, feature == .unlimitedScans {
                    isMatchingScan = true
                } else {
                    isMatchingScan = false
                }
                let isMatchingSelection: Bool
                if case .cleanupSelection = context, feature == .batchCleanup {
                    isMatchingSelection = true
                } else {
                    isMatchingSelection = false
                }
                guard !isMatchingScan, !isMatchingSelection else { continue }

                #expect(
                    PremiumAccessPolicy.decision(for: feature, context: context, isPremium: false) == .requiresPremium,
                    "\(feature) must stay locked when asked with the unrelated context \(context)"
                )
            }
        }
    }

    @Test func testControllerAgreesWithThePolicyForEveryFeatureAndContext() {
        let controller = PremiumAccessController()

        for feature in PremiumFeature.allCases {
            for context in contexts {
                #expect(
                    controller.access(to: feature, context: context) == PremiumAccessPolicy.decision(for: feature, context: context, isPremium: false),
                    "\(feature) in \(context) diverges between the controller and the policy"
                )
            }
        }
    }

    @Test func testUnlockingOneFeatureLeavesEveryOtherFeatureLocked() {
        for unlocked in PremiumFeature.allCases {
            let controller = PremiumAccessController(unlockedFeatures: [unlocked])

            for feature in PremiumFeature.allCases where feature != unlocked {
                // The two allowance-based features are still open to a free user
                // below their limit, so compare against the policy rather than
                // asserting a flat `.requiresPremium`.
                #expect(
                    controller.access(to: feature) == PremiumAccessPolicy.decision(for: feature, context: .none, isPremium: false),
                    "unlocking \(unlocked) changed the decision for \(feature)"
                )
            }
        }
    }

    @Test func testEveryFeatureIsCoveredByTheScanAndSelectionSplit() {
        // A new PremiumFeature added without deciding how it gates would fall
        // into `default` and be silently premium-only. That may be correct, but
        // it should be a decision, so this pins the current split.
        let allowanceBased: Set<PremiumFeature> = [.unlimitedScans, .batchCleanup]
        let alwaysPremium = Set(PremiumFeature.allCases).subtracting(allowanceBased)

        #expect(
            alwaysPremium == [.screenshotCleanup, .blurredPhotoCleanup, .advancedFilters, .cleanupReminderCustomization]
        )
        for feature in alwaysPremium {
            #expect(
                PremiumAccessPolicy.decision(for: feature, context: .none, isPremium: false) == .requiresPremium
            )
        }
    }
}
