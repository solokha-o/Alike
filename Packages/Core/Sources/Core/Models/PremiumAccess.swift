import Foundation

public enum PremiumFeature: String, CaseIterable, Hashable, Identifiable, Sendable, Codable {
    case unlimitedScans
    case screenshotCleanup
    case blurredPhotoCleanup
    case advancedFilters
    case batchCleanup
    case cleanupReminderCustomization

    public var id: String { rawValue }

#if DEBUG
    public var debugOverrideDefaultsKey: String {
        switch self {
        case .unlimitedScans:
            AppPreferenceKey.DebugPremium.unlimitedScans
        case .screenshotCleanup:
            AppPreferenceKey.DebugPremium.screenshotCleanup
        case .blurredPhotoCleanup:
            AppPreferenceKey.DebugPremium.blurredPhotoCleanup
        case .advancedFilters:
            AppPreferenceKey.DebugPremium.advancedFilters
        case .batchCleanup:
            AppPreferenceKey.DebugPremium.batchCleanup
        case .cleanupReminderCustomization:
            AppPreferenceKey.DebugPremium.cleanupReminders
        }
    }
#endif
}

public enum PremiumAccessContext: Equatable, Sendable {
    case none
    case scan(completedThisMonth: Int)
    case cleanupSelection(count: Int)
}

public enum PremiumAccessDecision: Equatable, Sendable {
    case allowed
    case requiresPremium

    public var isAllowed: Bool { self == .allowed }
}

public enum PremiumAccessPolicy {
    public static let monthlyFreeScanLimit = 3

    public static func decision(
        for feature: PremiumFeature,
        context: PremiumAccessContext = .none,
        isPremium: Bool
    ) -> PremiumAccessDecision {
        guard !isPremium else { return .allowed }

        switch (feature, context) {
        case (.unlimitedScans, .scan(let completedThisMonth)):
            return completedThisMonth < monthlyFreeScanLimit ? .allowed : .requiresPremium
        case (.batchCleanup, .cleanupSelection(let count)):
            return count <= 1 ? .allowed : .requiresPremium
        default:
            return .requiresPremium
        }
    }
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
    func access(
        to feature: PremiumFeature,
        context: PremiumAccessContext
    ) -> PremiumAccessDecision
}

public extension PremiumAccessControlling {
    func access(to feature: PremiumFeature) -> PremiumAccessDecision {
        access(to: feature, context: .none)
    }

    func hasAccess(to feature: PremiumFeature) -> Bool {
        access(to: feature).isAllowed
    }
}

public extension PremiumFeature {
    var categoryKind: CleanupCategoryKind? {
        switch self {
        case .screenshotCleanup:
            .screenshots
        case .blurredPhotoCleanup:
            .blurredPhotos
        case .unlimitedScans, .advancedFilters, .batchCleanup, .cleanupReminderCustomization:
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
