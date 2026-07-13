import Foundation

#if DEBUG

@MainActor
public struct MockPremiumAccessController: PremiumAccessControlling {
    public let unlockedFeatures: Set<PremiumFeature>
    public let entitlementState: PremiumEntitlementState

    public init(unlockedFeatures: Set<PremiumFeature> = []) {
        self.unlockedFeatures = unlockedFeatures
        self.entitlementState = PremiumEntitlementState(
            isPremium: !unlockedFeatures.isEmpty,
            source: .unknown
        )
    }

    public func access(
        to feature: PremiumFeature,
        context: PremiumAccessContext
    ) -> PremiumAccessDecision {
        if unlockedFeatures.contains(feature) {
            return .allowed
        }
        return PremiumAccessPolicy.decision(for: feature, context: context, isPremium: false)
    }
}

#endif
