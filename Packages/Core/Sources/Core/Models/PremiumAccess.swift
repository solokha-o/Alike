import Foundation

public enum PremiumFeature: String, Hashable, Identifiable, Sendable, Codable {
    case screenshotCleanup
    case blurredPhotoCleanup
    case cleanupReminders

    public var id: String { rawValue }

#if DEBUG
    public var debugOverrideDefaultsKey: String {
        switch self {
        case .screenshotCleanup:
            "debug.premium.screenshotCleanup"
        case .blurredPhotoCleanup:
            "debug.premium.blurredPhotoCleanup"
        case .cleanupReminders:
            "debug.premium.cleanupReminders"
        }
    }
#endif
}

public enum PremiumEntitlementSource: String, Codable, Equatable, Sendable {
    case unknown
    case cached
    case verified
    case stale
}

public struct PremiumEntitlementState: Codable, Equatable, Sendable {
    public let isPremium: Bool
    public let source: PremiumEntitlementSource
    public let productID: String?
    public let expirationDate: Date?

    public init(
        isPremium: Bool = false,
        source: PremiumEntitlementSource = .unknown,
        productID: String? = nil,
        expirationDate: Date? = nil
    ) {
        self.isPremium = isPremium
        self.source = source
        self.productID = productID
        self.expirationDate = expirationDate
    }

    public static let unknown = PremiumEntitlementState()
}

@MainActor
public protocol PremiumAccessControlling: Sendable {
    var entitlementState: PremiumEntitlementState { get }
    func hasAccess(to feature: PremiumFeature) -> Bool
}

public extension PremiumFeature {
    var categoryKind: CleanupCategoryKind? {
        switch self {
        case .screenshotCleanup:
            .screenshots
        case .blurredPhotoCleanup:
            .blurredPhotos
        case .cleanupReminders:
            nil
        }
    }
}

@MainActor
public struct PremiumAccessController: PremiumAccessControlling {
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
