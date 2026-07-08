import Foundation

public enum PremiumFeature: String, Hashable, Identifiable, Sendable, Codable {
    case screenshotCleanup
    case blurredPhotoCleanup

    public var id: String { rawValue }

#if DEBUG
    public var debugOverrideDefaultsKey: String {
        switch self {
        case .screenshotCleanup:
            "debug.premium.screenshotCleanup"
        case .blurredPhotoCleanup:
            "debug.premium.blurredPhotoCleanup"
        }
    }
#endif
}

public protocol PremiumAccessControlling: Sendable {
    func hasAccess(to feature: PremiumFeature) -> Bool
}

public extension PremiumFeature {
    var categoryKind: CleanupCategoryKind {
        switch self {
        case .screenshotCleanup:
            .screenshots
        case .blurredPhotoCleanup:
            .blurredPhotos
        }
    }
}

public struct PremiumAccessController: PremiumAccessControlling {
    public let unlockedFeatures: Set<PremiumFeature>

    public init(unlockedFeatures: Set<PremiumFeature> = []) {
        self.unlockedFeatures = unlockedFeatures
    }

    public func hasAccess(to feature: PremiumFeature) -> Bool {
        unlockedFeatures.contains(feature)
    }
}
