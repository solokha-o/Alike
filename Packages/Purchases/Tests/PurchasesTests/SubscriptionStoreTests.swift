import Foundation
import Testing
@testable import Purchases
import Core

@MainActor
@Suite struct SubscriptionStoreTests {
    private let catalog = SubscriptionCatalog(
        monthlyID: "test.alike.monthly",
        yearlyID: "test.alike.yearly"
    )

    @Test func testProductionCatalogUsesPermanentProductIdentifiers() {
        let catalog = SubscriptionCatalog.production

        #expect(catalog.isConfigured)
        #expect(catalog.productID(for: .monthly) == "com.alike.app.pro.monthly")
        #expect(catalog.productID(for: .yearly) == "com.alike.app.pro.yearly")
        #expect(catalog.plan(for: "com.alike.app.pro.monthly") == .monthly)
        #expect(catalog.plan(for: "com.alike.app.pro.yearly") == .yearly)
        #expect(catalog.allProductIDs.count == SubscriptionPlan.allCases.count)
        #expect(catalog.allProductIDs.allSatisfy { $0.hasPrefix("com.alike.app.pro.") })
    }

    @Test func testPlanPresentationAndCommercialMetadata() {
        #expect(SubscriptionPlan.presentationOrder == [.yearly, .monthly])
        #expect(SubscriptionPlan.yearly.isPrimary)
        #expect(!SubscriptionPlan.monthly.isPrimary)
        #expect(SubscriptionPlan.monthly.advertisedPriceUSD == Decimal(string: "6.99"))
        #expect(SubscriptionPlan.yearly.advertisedPriceUSD == Decimal(string: "39.99"))
        #expect(SubscriptionPlan.monthly.configuredTrialDays == nil)
        #expect(SubscriptionPlan.yearly.configuredTrialDays == 7)
    }

    @Test func testProductionCatalogLoadsBothProducts() async {
        let client = MockStoreKitClient(
            products: [
                StorefrontProduct(
                    id: "com.alike.app.pro.monthly",
                    displayName: "Alike Pro Monthly",
                    displayPrice: "$6.99"
                ),
                StorefrontProduct(
                    id: "com.alike.app.pro.yearly",
                    displayName: "Alike Pro Yearly",
                    displayPrice: "$39.99"
                )
            ]
        )
        let store = SubscriptionStore(
            catalog: .production,
            client: client,
            defaults: UserDefaults(suiteName: "PurchasesTests.\(UUID().uuidString)")!,
            cacheKey: UUID().uuidString
        )

        await store.loadProducts()

        #expect(store.productLoadState == .loaded)
        #expect(store.products.count == SubscriptionPlan.allCases.count)
    }

    @Test func testLoadProductsMapsEveryPlan() async {
        let client = MockStoreKitClient(
            products: [
                StorefrontProduct(
                    id: "test.alike.monthly",
                    displayName: "Monthly",
                    displayPrice: "$6.99",
                    price: Decimal(string: "6.99")!
                ),
                StorefrontProduct(
                    id: "test.alike.yearly",
                    displayName: "Yearly",
                    displayPrice: "$39.99",
                    price: Decimal(string: "39.99")!
                )
            ]
        )
        let store = makeStore(client: client)

        await store.loadProducts()

        #expect(store.productLoadState == .loaded)
        #expect(store.products[.monthly]?.displayPrice == "$6.99")
        #expect(store.products[.monthly]?.price == Decimal(string: "6.99"))
        #expect(store.products[.yearly]?.plan == .yearly)
        #expect(store.products[.yearly]?.price == Decimal(string: "39.99"))
    }

    @Test func testRefreshGrantsAccessForVerifiedActiveEntitlement() async {
        let client = MockStoreKitClient(entitlements: [
            entitlement(productID: "test.alike.yearly", expirationDate: .distantFuture)
        ])
        let store = makeStore(client: client)

        await store.refreshEntitlements()

        #expect(store.entitlementState.isPremium)
        #expect(store.entitlementState.source == .verified)
        #expect(store.hasAccess(to: .screenshotCleanup))
        #expect(store.hasAccess(to: .cleanupReminderCustomization))
    }

    @Test func testRefreshRejectsExpiredRevokedAndUnverifiedEntitlements() async {
        let client = MockStoreKitClient(entitlements: [
            entitlement(productID: "test.alike.monthly", expirationDate: .distantPast),
            entitlement(productID: "test.alike.yearly", expirationDate: .distantFuture, revocationDate: Date()),
            entitlement(productID: "test.alike.yearly", expirationDate: .distantFuture, isVerified: false)
        ])
        let store = makeStore(client: client)

        await store.refreshEntitlements()

        #expect(!store.entitlementState.isPremium)
        #expect(!(store.hasAccess(to: .blurredPhotoCleanup)))
    }

    @Test func testPurchaseUsesVerifiedPayloadWhenCurrentEntitlementsAreEmpty() async throws {
        let client = MockStoreKitClient(
            products: [
                StorefrontProduct(id: "test.alike.monthly", displayName: "Monthly", displayPrice: "$6.99"),
                StorefrontProduct(id: "test.alike.yearly", displayName: "Yearly", displayPrice: "$39.99")
            ],
            purchaseOutcome: .success(entitlement(productID: "test.alike.yearly", expirationDate: .distantFuture))
        )
        let store = makeStore(client: client)
        await store.loadProducts()

        let outcome = try await store.purchase(plan: .yearly)

        #expect(outcome == .purchased)
        #expect(store.entitlementState.isPremium)
        #expect(store.entitlementState.productID == "test.alike.yearly")
        #expect(client.purchasedProductID == "test.alike.yearly")
    }

    @Test func testCachedAccessReconcilesBeforeSuspendedProductLoad() async throws {
        let productRequests = ControlledRequest<[StorefrontProduct]>()
        let client = MockStoreKitClient(productRequests: productRequests)
        let suiteName = "PurchasesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let cacheKey = UUID().uuidString
        let cached = PremiumEntitlementState(
            isPremium: true,
            source: .verified,
            productID: "test.alike.yearly",
            expirationDate: .distantFuture
        )
        defaults.set(try JSONEncoder().encode(cached), forKey: cacheKey)
        let store = SubscriptionStore(catalog: catalog, client: client, defaults: defaults, cacheKey: cacheKey)

        let startTask = Task { await store.start() }
        await productRequests.waitForRequestCount(1)

        #expect(!store.entitlementState.isPremium)
        #expect(store.entitlementState.source == .verified)

        await productRequests.resumeRequest(at: 0, returning: storefrontProducts())
        await startTask.value
    }

    @Test func testFailedReloadClearsPreviouslyLoadedProducts() async {
        let client = MockStoreKitClient(products: storefrontProducts())
        let store = makeStore(client: client)
        await store.loadProducts()
        #expect(store.productLoadState == .loaded)

        client.products = [storefrontProducts()[0]]
        await store.loadProducts()

        #expect(store.products.isEmpty)
        guard case .failed = store.productLoadState else {
            Issue.record("Expected the reload to fail")
            return
        }
    }

    @Test func testOlderRefreshCannotOverwriteNewerResult() async {
        let requests = ControlledRequest<[StoreKitEntitlement]>()
        let client = MockStoreKitClient(entitlementRequests: requests)
        let store = makeStore(client: client)

        let olderRefresh = Task { await store.refreshEntitlements() }
        await requests.waitForRequestCount(1)
        let newerRefresh = Task { await store.refreshEntitlements() }
        await requests.waitForRequestCount(2)

        await requests.resumeRequest(
            at: 1,
            returning: [entitlement(productID: "test.alike.yearly", expirationDate: .distantFuture)]
        )
        await newerRefresh.value
        await requests.resumeRequest(at: 0, returning: [])
        await olderRefresh.value

        #expect(store.entitlementState.isPremium)
        #expect(store.entitlementState.productID == "test.alike.yearly")
    }

    @Test func testCancelledRefreshDoesNotOverwriteEntitlementState() async {
        let requests = ControlledRequest<[StoreKitEntitlement]>()
        let client = MockStoreKitClient(
            entitlements: [entitlement(productID: "test.alike.monthly", expirationDate: .distantFuture)]
        )
        let store = makeStore(client: client)
        await store.refreshEntitlements()
        client.entitlementRequests = requests

        let refresh = Task { await store.refreshEntitlements() }
        await requests.waitForRequestCount(1)
        refresh.cancel()
        await requests.resumeRequest(at: 0, returning: [])
        await refresh.value

        #expect(store.entitlementState.isPremium)
        #expect(store.entitlementState.productID == "test.alike.monthly")
    }

    @Test func testPurchaseAndRestoreSuccessClearEarlierErrors() async throws {
        let client = MockStoreKitClient(products: storefrontProducts())
        let store = makeStore(client: client)
        await store.loadProducts()

        client.purchaseError = TestFailure.expected
        do {
            _ = try await store.purchase(plan: .yearly)
            Issue.record("Expected purchase to fail")
        } catch {}
        #expect(store.lastError != nil)

        client.purchaseError = nil
        client.purchaseOutcome = .cancelled
        let retryOutcome = try await store.purchase(plan: .yearly)
        #expect(retryOutcome == .cancelled)
        #expect(store.lastError == nil)

        client.syncError = TestFailure.expected
        do {
            try await store.restorePurchases()
            Issue.record("Expected restore to fail")
        } catch {}
        #expect(store.lastError != nil)

        client.syncError = nil
        try await store.restorePurchases()
        #expect(store.lastError == nil)
    }

    @Test func testRestoreSyncsThenRefreshesEntitlement() async throws {
        let client = MockStoreKitClient(entitlements: [
            entitlement(productID: "test.alike.monthly", expirationDate: .distantFuture)
        ])
        let store = makeStore(client: client)

        try await store.restorePurchases()

        #expect(client.didSync)
        #expect(store.entitlementState.isPremium)
    }

    @Test func testExpiredCachedEntitlementDoesNotGrantAccessBeforeReconciliation() async throws {
        let suiteName = "PurchasesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let cacheKey = UUID().uuidString
        let cached = PremiumEntitlementState(
            isPremium: true,
            source: .verified,
            productID: "test.alike.yearly",
            expirationDate: .distantPast
        )
        defaults.set(try JSONEncoder().encode(cached), forKey: cacheKey)
        let store = SubscriptionStore(
            catalog: .unconfigured,
            client: MockStoreKitClient(),
            defaults: defaults,
            cacheKey: cacheKey
        )

        await store.start()

        #expect(!store.entitlementState.isPremium)
        #expect(store.entitlementState.source == .cached)
        #expect(store.entitlementState.productID == nil)
    }

    /// An expired Premium cache for a subscription renewed since: until StoreKit answers
    /// the store reads as free, so it must also read as *not settled* — that is what
    /// lets a caller tell "free" from "free until the check finishes".
    @Test func testExpiredPremiumCacheIsNotSettledUntilDelayedVerificationGrantsAccess() async throws {
        let defaults = UserDefaults(suiteName: "PurchasesTests.\(UUID().uuidString)")!
        let cacheKey = UUID().uuidString
        let cached = PremiumEntitlementState(
            isPremium: true,
            source: .verified,
            productID: "test.alike.yearly",
            expirationDate: .distantPast
        )
        defaults.set(try JSONEncoder().encode(cached), forKey: cacheKey)
        let entitlementRequests = ControlledRequest<[StoreKitEntitlement]>()
        let store = SubscriptionStore(
            catalog: catalog,
            client: MockStoreKitClient(entitlementRequests: entitlementRequests),
            defaults: defaults,
            cacheKey: cacheKey
        )

        let start = Task { await store.start() }
        await entitlementRequests.waitForRequestCount(1)

        #expect(!store.entitlementState.isPremium)
        #expect(store.entitlementState.source == .cached)
        #expect(!store.isEntitlementSettled)

        await entitlementRequests.resumeRequest(
            at: 0,
            returning: [entitlement(productID: "test.alike.yearly", expirationDate: .distantFuture)]
        )
        await start.value

        #expect(store.entitlementState.isPremium)
        #expect(store.entitlementState.source == .verified)
        #expect(store.isEntitlementSettled)
    }

    /// The fallback: a check that fails (offline) still settles, on the cached state,
    /// so callers are not held forever.
    @Test func testAFailedEntitlementCheckSettlesOnTheCachedState() async {
        let client = MockStoreKitClient()
        client.entitlementError = TestFailure.expected
        let store = makeStore(client: client)

        await store.start()

        #expect(!store.entitlementState.isPremium)
        #expect(store.isEntitlementSettled)
    }

    @Test func testAnUnconfiguredCatalogSettlesImmediately() async {
        let store = SubscriptionStore(
            catalog: .unconfigured,
            client: MockStoreKitClient(),
            defaults: UserDefaults(suiteName: "PurchasesTests.\(UUID().uuidString)")!,
            cacheKey: UUID().uuidString
        )

        await store.start()

        #expect(store.isEntitlementSettled)
    }

    private func makeStore(client: MockStoreKitClient) -> SubscriptionStore {
        let defaults = UserDefaults(suiteName: "PurchasesTests.\(UUID().uuidString)")!
        return SubscriptionStore(catalog: catalog, client: client, defaults: defaults, cacheKey: UUID().uuidString)
    }

    private func storefrontProducts() -> [StorefrontProduct] {
        [
            StorefrontProduct(id: "test.alike.monthly", displayName: "Monthly", displayPrice: "$6.99"),
            StorefrontProduct(id: "test.alike.yearly", displayName: "Yearly", displayPrice: "$39.99")
        ]
    }

    private func entitlement(
        productID: String,
        expirationDate: Date?,
        revocationDate: Date? = nil,
        isVerified: Bool = true
    ) -> StoreKitEntitlement {
        StoreKitEntitlement(
            productID: productID,
            expirationDate: expirationDate,
            revocationDate: revocationDate,
            isUpgraded: false,
            isVerified: isVerified
        )
    }
}

private final class MockStoreKitClient: StoreKitClient, @unchecked Sendable {
    var products: [StorefrontProduct]
    var entitlements: [StoreKitEntitlement]
    var purchaseOutcome: StoreKitPurchaseOutcome
    var purchasedProductID: String?
    var didSync = false
    var purchaseError: Error?
    var syncError: Error?
    var entitlementError: Error?
    var entitlementRequests: ControlledRequest<[StoreKitEntitlement]>?
    let productRequests: ControlledRequest<[StorefrontProduct]>?

    init(
        products: [StorefrontProduct] = [],
        entitlements: [StoreKitEntitlement] = [],
        purchaseOutcome: StoreKitPurchaseOutcome = .cancelled,
        entitlementRequests: ControlledRequest<[StoreKitEntitlement]>? = nil,
        productRequests: ControlledRequest<[StorefrontProduct]>? = nil
    ) {
        self.products = products
        self.entitlements = entitlements
        self.purchaseOutcome = purchaseOutcome
        self.entitlementRequests = entitlementRequests
        self.productRequests = productRequests
    }

    func loadProducts(ids: Set<String>) async throws -> [StorefrontProduct] {
        if let productRequests { return await productRequests.request() }
        return products
    }

    func purchase(productID: String) async throws -> StoreKitPurchaseOutcome {
        purchasedProductID = productID
        if let purchaseError { throw purchaseError }
        return purchaseOutcome
    }

    func sync() async throws {
        didSync = true
        if let syncError { throw syncError }
    }

    func currentEntitlements() async throws -> [StoreKitEntitlement] {
        if let entitlementError { throw entitlementError }
        if let entitlementRequests { return await entitlementRequests.request() }
        return entitlements
    }

    func transactionUpdates() -> AsyncStream<StoreKitTransactionUpdate> {
        AsyncStream { $0.finish() }
    }
}

private enum TestFailure: Error {
    case expected
}

private actor ControlledRequest<Value: Sendable> {
    private var requests: [CheckedContinuation<Value, Never>?] = []
    private var countWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func request() async -> Value {
        await withCheckedContinuation { continuation in
            requests.append(continuation)
            resumeSatisfiedWaiters()
        }
    }

    func waitForRequestCount(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((count, continuation))
        }
    }

    func resumeRequest(at index: Int, returning value: Value) {
        guard requests.indices.contains(index), let continuation = requests[index] else { return }
        requests[index] = nil
        continuation.resume(returning: value)
    }

    private func resumeSatisfiedWaiters() {
        let satisfied = countWaiters.filter { requests.count >= $0.count }
        countWaiters.removeAll { requests.count >= $0.count }
        for waiter in satisfied {
            waiter.continuation.resume()
        }
    }
}
