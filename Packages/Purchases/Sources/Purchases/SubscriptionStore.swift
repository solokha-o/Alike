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
    private var reconciliationGeneration = 0

    public init(catalog: SubscriptionCatalog = .production) {
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

    public func access(
        to feature: PremiumFeature,
        context: PremiumAccessContext
    ) -> PremiumAccessDecision {
        PremiumAccessPolicy.decision(
            for: feature,
            context: context,
            isPremium: entitlementState.isPremium
        )
    }

    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        loadCachedEntitlement()
        startTransactionObservation()
        await refreshEntitlements()
        await loadProducts()
    }

    public func loadProducts() async {
        guard catalog.isConfigured else {
            products = [:]
            productLoadState = .unconfigured
            return
        }

        products = [:]
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
                    displayPrice: product.displayPrice,
                    price: product.price
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
        await reconcileEntitlements()
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
                applyEntitlements([entitlement])
                lastError = nil
                return .purchased
            case .pending:
                lastError = nil
                return .pending
            case .cancelled:
                lastError = nil
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
            lastError = nil
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
            for await update in client.transactionUpdates() {
                guard let self else { return }
                await self.reconcileEntitlements(supplementing: update.entitlement)
            }
        }
    }

    private func reconcileEntitlements(supplementing supplementalEntitlement: StoreKitEntitlement? = nil) async {
        guard catalog.isConfigured else { return }

        reconciliationGeneration &+= 1
        let generation = reconciliationGeneration

        do {
            var entitlements = try await client.currentEntitlements()
            try Task.checkCancellation()
            guard generation == reconciliationGeneration else { return }

            if let supplementalEntitlement, supplementalEntitlement.isVerified {
                entitlements.removeAll { $0.productID == supplementalEntitlement.productID }
                entitlements.append(supplementalEntitlement)
            }

            applyEntitlements(entitlements)
        } catch is CancellationError {
            guard
                generation == reconciliationGeneration,
                let supplementalEntitlement,
                supplementalEntitlement.isVerified
            else { return }
            applyEntitlements([supplementalEntitlement])
        } catch {
            guard
                generation == reconciliationGeneration,
                let supplementalEntitlement,
                supplementalEntitlement.isVerified
            else { return }
            applyEntitlements([supplementalEntitlement])
        }
    }

    private func applyEntitlements(_ entitlements: [StoreKitEntitlement]) {
        let entitlement = activeEntitlement(in: entitlements)
        setEntitlementState(
            PremiumEntitlementState(
                isPremium: entitlement != nil,
                source: .verified,
                productID: entitlement?.productID,
                expirationDate: entitlement?.expirationDate
            )
        )
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

    public func access(
        to feature: PremiumFeature,
        context: PremiumAccessContext
    ) -> PremiumAccessDecision {
        if defaults.bool(forKey: feature.debugOverrideDefaultsKey) {
            return .allowed
        }
        return base.access(to: feature, context: context)
    }
}
#endif
