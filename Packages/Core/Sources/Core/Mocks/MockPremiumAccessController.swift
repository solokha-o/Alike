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

    public func hasAccess(to feature: PremiumFeature) -> Bool {
        unlockedFeatures.contains(feature)
    }
}

#endif
