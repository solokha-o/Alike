import Foundation
import Observation
import Core

@MainActor
@Observable
public final class SubscriptionStore: PremiumAccessControlling {
    public private(set) var products: [SubscriptionPlan: SubscriptionProduct] = [:]
    public private(set) var productLoadState: ProductLoadState = .idle
    public private(set) var entitlementState: PremiumEntitlementState = .unknown
    public private(set) var lastError: SubscriptionStoreError?

    private let catalog: SubscriptionCatalog
    private let client: any StoreKitClient
    private let defaults: UserDefaults
    private let cacheKey: String
    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    public init(catalog: SubscriptionCatalog = .unconfigured) {
        self.catalog = catalog
        self.client = AppStoreKitClient()
        self.defaults = .standard
        self.cacheKey = "subscription.entitlement.v1"
    }

    init(
        catalog: SubscriptionCatalog,
        client: any StoreKitClient,
        defaults: UserDefaults = .standard,
        cacheKey: String = "subscription.entitlement.v1"
    ) {
        self.catalog = catalog
        self.client = client
        self.defaults = defaults
        self.cacheKey = cacheKey
    }

    public func hasAccess(to feature: PremiumFeature) -> Bool {
        entitlementState.isPremium
    }

    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        loadCachedEntitlement()
        startTransactionObservation()
        await loadProducts()
        await refreshEntitlements()
    }

    public func loadProducts() async {
        guard catalog.isConfigured else {
            productLoadState = .unconfigured
            return
        }

        productLoadState = .loading
        do {
            let storefrontProducts = try await client.loadProducts(ids: catalog.allProductIDs)
            var loadedProducts: [SubscriptionPlan: SubscriptionProduct] = [:]
            for product in storefrontProducts {
                guard let plan = catalog.plan(for: product.id) else { continue }
                loadedProducts[plan] = SubscriptionProduct(
                    id: product.id,
                    plan: plan,
                    displayName: product.displayName,
                    displayPrice: product.displayPrice
                )
            }

            guard loadedProducts.count == SubscriptionPlan.allCases.count else {
                throw SubscriptionStoreError.productLoadingFailed("One or more subscription products are unavailable.")
            }
            products = loadedProducts
            productLoadState = .loaded
            lastError = nil
        } catch let error as SubscriptionStoreError {
            productLoadState = .failed(error.localizedDescription)
            lastError = error
        } catch {
            let storeError = SubscriptionStoreError.productLoadingFailed(error.localizedDescription)
            productLoadState = .failed(storeError.localizedDescription)
            lastError = storeError
        }
    }

    public func refreshEntitlements() async {
        guard catalog.isConfigured else { return }
        let entitlement = activeEntitlement(in: await client.currentEntitlements())
        setEntitlementState(
            PremiumEntitlementState(
                isPremium: entitlement != nil,
                source: .verified,
                productID: entitlement?.productID,
                expirationDate: entitlement?.expirationDate
            )
        )
    }

    public func purchase(plan: SubscriptionPlan) async throws -> PurchaseOutcome {
        guard let productID = catalog.productID(for: plan) else {
            throw SubscriptionStoreError.catalogNotConfigured
        }
        guard products[plan] != nil else {
            throw SubscriptionStoreError.productUnavailable(plan)
        }

        do {
            switch try await client.purchase(productID: productID) {
            case .success(let entitlement):
                guard entitlement.isVerified else {
                    throw SubscriptionStoreError.purchaseFailed("The purchase could not be verified.")
                }
                await refreshEntitlements()
                return .purchased
            case .pending:
                return .pending
            case .cancelled:
                return .cancelled
            }
        } catch let error as SubscriptionStoreError {
            lastError = error
            throw error
        } catch {
            let storeError = SubscriptionStoreError.purchaseFailed(error.localizedDescription)
            lastError = storeError
            throw storeError
        }
    }

    public func restorePurchases() async throws {
        do {
            try await client.sync()
            await refreshEntitlements()
        } catch {
            let storeError = SubscriptionStoreError.restoreFailed(error.localizedDescription)
            lastError = storeError
            throw storeError
        }
    }

    public func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        hasStarted = false
    }

    private func startTransactionObservation() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self, client] in
            for await _ in client.transactionUpdates() {
                guard let self else { return }
                await self.refreshEntitlements()
            }
        }
    }

    private func activeEntitlement(in entitlements: [StoreKitEntitlement]) -> StoreKitEntitlement? {
        let now = Date()
        return entitlements
            .filter {
                $0.isVerified &&
                $0.revocationDate == nil &&
                !$0.isUpgraded &&
                ($0.expirationDate == nil || $0.expirationDate! > now) &&
                catalog.plan(for: $0.productID) != nil
            }
            .max { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
    }

    private func loadCachedEntitlement() {
        guard
            let data = defaults.data(forKey: cacheKey),
            let cached = try? JSONDecoder().decode(PremiumEntitlementState.self, from: data)
        else { return }

        let isKnownExpired = cached.expirationDate.map { $0 <= Date() } ?? false
        entitlementState = PremiumEntitlementState(
            isPremium: cached.isPremium && !isKnownExpired,
            source: .cached,
            productID: isKnownExpired ? nil : cached.productID,
            expirationDate: cached.expirationDate
        )
    }

    private func setEntitlementState(_ state: PremiumEntitlementState) {
        entitlementState = state
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: cacheKey)
        }
    }
}

#if DEBUG
@MainActor
public final class DebugPremiumAccessController: PremiumAccessControlling {
    private let base: any PremiumAccessControlling
    private let defaults: UserDefaults

    public init(base: any PremiumAccessControlling, defaults: UserDefaults = .standard) {
        self.base = base
        self.defaults = defaults
    }

    public var entitlementState: PremiumEntitlementState { base.entitlementState }

    public func hasAccess(to feature: PremiumFeature) -> Bool {
        defaults.bool(forKey: feature.debugOverrideDefaultsKey) || base.hasAccess(to: feature)
    }
}
#endif
