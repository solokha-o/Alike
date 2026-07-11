import Foundation

public enum SubscriptionPlan: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case monthly
    case yearly

    public var id: String { rawValue }

    public var advertisedPriceUSD: Decimal {
        switch self {
        case .monthly: 6.99
        case .yearly: 39.99
        }
    }

    public var trialDays: Int? {
        switch self {
        case .monthly: nil
        case .yearly: 7
        }
    }
}

public struct SubscriptionCatalog: Equatable, Sendable {
    private let productIDs: [SubscriptionPlan: String]

    public init(monthlyID: String, yearlyID: String) {
        precondition(!monthlyID.isEmpty && !yearlyID.isEmpty, "Subscription product IDs must not be empty.")
        precondition(monthlyID != yearlyID, "Subscription product IDs must be unique.")
        self.productIDs = [.monthly: monthlyID, .yearly: yearlyID]
    }

    private init(productIDs: [SubscriptionPlan: String]) {
        self.productIDs = productIDs
    }

    /// Used until Task 09 supplies the App Store and local StoreKit identifiers.
    public static let unconfigured = SubscriptionCatalog(productIDs: [:])

    public var isConfigured: Bool {
        Set(productIDs.keys) == Set(SubscriptionPlan.allCases)
    }

    public func productID(for plan: SubscriptionPlan) -> String? {
        productIDs[plan]
    }

    public func plan(for productID: String) -> SubscriptionPlan? {
        productIDs.first(where: { $0.value == productID })?.key
    }

    var allProductIDs: Set<String> {
        Set(productIDs.values)
    }
}

public struct SubscriptionProduct: Equatable, Sendable, Identifiable {
    public let id: String
    public let plan: SubscriptionPlan
    public let displayName: String
    public let displayPrice: String

    init(id: String, plan: SubscriptionPlan, displayName: String, displayPrice: String) {
        self.id = id
        self.plan = plan
        self.displayName = displayName
        self.displayPrice = displayPrice
    }
}

public enum ProductLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case unconfigured
    case failed(String)
}

public enum PurchaseOutcome: Equatable, Sendable {
    case purchased
    case pending
    case cancelled
}

public enum SubscriptionStoreError: Error, Equatable, LocalizedError, Sendable {
    case catalogNotConfigured
    case productUnavailable(SubscriptionPlan)
    case productLoadingFailed(String)
    case purchaseFailed(String)
    case restoreFailed(String)

    public var errorDescription: String? {
        switch self {
        case .catalogNotConfigured: "Subscription products are not configured yet."
        case .productUnavailable(let plan): "The \(plan.rawValue) subscription is unavailable."
        case .productLoadingFailed(let message), .purchaseFailed(let message), .restoreFailed(let message): message
        }
    }
}

struct StorefrontProduct: Sendable {
    let id: String
    let displayName: String
    let displayPrice: String
}

struct StoreKitEntitlement: Sendable {
    let productID: String
    let expirationDate: Date?
    let revocationDate: Date?
    let isUpgraded: Bool
    let isVerified: Bool
}

enum StoreKitPurchaseOutcome: Sendable {
    case success(StoreKitEntitlement)
    case pending
    case cancelled
}

struct StoreKitTransactionUpdate: Sendable {
    let entitlement: StoreKitEntitlement
}
