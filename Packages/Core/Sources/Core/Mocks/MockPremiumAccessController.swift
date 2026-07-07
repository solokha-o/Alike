import Foundation

#if DEBUG

public struct MockPremiumAccessController: PremiumAccessControlling {
    public let unlockedFeatures: Set<PremiumFeature>

    public init(unlockedFeatures: Set<PremiumFeature> = []) {
        self.unlockedFeatures = unlockedFeatures
    }

    public func hasAccess(to feature: PremiumFeature) -> Bool {
        unlockedFeatures.contains(feature)
    }
}

#endif
