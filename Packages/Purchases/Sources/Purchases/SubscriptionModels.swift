import Foundation

public enum SubscriptionPlan: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case monthly
    case yearly

    public var id: String { rawValue }

    /// Stable paywall ordering. StoreKit remains the source of localized product data.
    public static let presentationOrder: [SubscriptionPlan] = [.yearly, .monthly]

    public var isPrimary: Bool {
        self == .yearly
    }

    public var advertisedPriceUSD: Decimal {
        switch self {
        case .monthly: Decimal(string: "8.99")!
        case .yearly: Decimal(string: "39.99")!
        }
    }

    /// The introductory offer configured for this plan. This does not indicate
    /// whether the current customer is eligible; query StoreKit before showing trial copy.
    public var configuredTrialDays: Int? {
        switch self {
        case .monthly: nil
        case .yearly: 7
        }
    }
}

public struct SubscriptionCatalog: Equatable, Sendable {
    /// The product each plan sells today: the paywall loads and purchases these.
    private let productIDs: [SubscriptionPlan: String]
    /// Further product IDs that belong to a plan — an earlier price point, for one.
    /// They grant Premium to whoever owns them, but the paywall never sells them.
    private let additionalProductIDs: [SubscriptionPlan: Set<String>]

    /// The non-expiring Premium purchase, when the catalog has one. It is not a
    /// `SubscriptionPlan`: it has no duration, no trial and no subscription group.
    public let lifetimeProductID: String?

    /// - Parameters:
    ///   - additionalProductIDs: IDs that still grant a plan's Premium but are no
    ///     longer sold. Never drop an ID from here once it shipped: its owners
    ///     would lose Premium.
    ///   - lifetimeProductID: The non-consumable that grants Premium without an
    ///     expiration date. Never drop it once it shipped, for the same reason.
    public init(
        monthlyID: String,
        yearlyID: String,
        additionalProductIDs: [SubscriptionPlan: Set<String>] = [:],
        lifetimeProductID: String? = nil
    ) {
        let primaryIDs = [monthlyID, yearlyID]
        let extraIDs = additionalProductIDs.values.flatMap { $0 }
        let everyID = primaryIDs + extraIDs + (lifetimeProductID.map { [$0] } ?? [])
        precondition(everyID.allSatisfy { !$0.isEmpty }, "Subscription product IDs must not be empty.")
        precondition(Set(everyID).count == everyID.count, "Subscription product IDs must be unique.")
        productIDs = [.monthly: monthlyID, .yearly: yearlyID]
        self.additionalProductIDs = additionalProductIDs.filter { !$0.value.isEmpty }
        self.lifetimeProductID = lifetimeProductID
    }

    private init(productIDs: [SubscriptionPlan: String]) {
        self.productIDs = productIDs
        additionalProductIDs = [:]
        lifetimeProductID = nil
    }

    /// The App Store Connect and local StoreKit product identifier source of truth.
    ///
    /// The lifetime ID is known before App Store Connect sells it: StoreKit omits an
    /// unknown product, so until then the store behaves as with the two plans alone.
    public static let production = SubscriptionCatalog(
        monthlyID: "com.alike.app.pro.monthly",
        yearlyID: "com.alike.app.pro.yearly",
        lifetimeProductID: "com.alike.app.pro.lifetime"
    )

    /// Available for isolated tests and previews that intentionally omit StoreKit products.
    public static let unconfigured = SubscriptionCatalog(productIDs: [:])

    public var isConfigured: Bool {
        Set(productIDs.keys) == Set(SubscriptionPlan.allCases)
    }

    /// The product the paywall sells for `plan`.
    public func productID(for plan: SubscriptionPlan) -> String? {
        productIDs[plan]
    }

    /// The plan a product belongs to — the sold product or an additional one.
    /// `nil` for the lifetime product and for unknown IDs.
    public func plan(for productID: String) -> SubscriptionPlan? {
        if let plan = productIDs.first(where: { $0.value == productID })?.key {
            return plan
        }
        return additionalProductIDs.first(where: { $0.value.contains(productID) })?.key
    }

    /// Whether owning `productID` grants Premium.
    public func grantsPremium(productID: String) -> Bool {
        plan(for: productID) != nil || productID == lifetimeProductID
    }

    /// The products each plan sells today.
    var allProductIDs: Set<String> {
        Set(productIDs.values)
    }

    /// Everything the paywall may ask StoreKit for: the plans and the lifetime product.
    var storefrontProductIDs: Set<String> {
        allProductIDs.union(lifetimeProductID.map { [$0] } ?? [])
    }
}

/// The non-expiring Premium purchase, as StoreKit describes it for this storefront.
public struct LifetimeProduct: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let displayPrice: String
    public let price: Decimal
}

public struct SubscriptionProduct: Equatable, Sendable, Identifiable {
    public let id: String
    public let plan: SubscriptionPlan
    public let displayName: String
    public let displayPrice: String
    public let price: Decimal
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
    let price: Decimal

    init(id: String, displayName: String, displayPrice: String, price: Decimal = .zero) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.price = price
    }
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
