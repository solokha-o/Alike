import XCTest
@testable import Purchases
import Core

@MainActor
final class SubscriptionStoreTests: XCTestCase {
    private let catalog = SubscriptionCatalog(
        monthlyID: "test.alike.monthly",
        yearlyID: "test.alike.yearly"
    )

    func testProductionCatalogUsesPermanentProductIdentifiers() {
        let catalog = SubscriptionCatalog.production

        XCTAssertTrue(catalog.isConfigured)
        XCTAssertEqual(catalog.productID(for: .monthly), "com.alike.app.pro.monthly")
        XCTAssertEqual(catalog.productID(for: .yearly), "com.alike.app.pro.yearly")
        XCTAssertEqual(catalog.plan(for: "com.alike.app.pro.monthly"), .monthly)
        XCTAssertEqual(catalog.plan(for: "com.alike.app.pro.yearly"), .yearly)
        XCTAssertEqual(catalog.allProductIDs.count, SubscriptionPlan.allCases.count)
        XCTAssertTrue(catalog.allProductIDs.allSatisfy { $0.hasPrefix("com.alike.app.pro.") })
    }

    func testPlanPresentationAndCommercialMetadata() {
        XCTAssertEqual(SubscriptionPlan.presentationOrder, [.yearly, .monthly])
        XCTAssertTrue(SubscriptionPlan.yearly.isPrimary)
        XCTAssertFalse(SubscriptionPlan.monthly.isPrimary)
        XCTAssertEqual(SubscriptionPlan.monthly.advertisedPriceUSD, Decimal(string: "6.99"))
        XCTAssertEqual(SubscriptionPlan.yearly.advertisedPriceUSD, Decimal(string: "39.99"))
        XCTAssertNil(SubscriptionPlan.monthly.configuredTrialDays)
        XCTAssertEqual(SubscriptionPlan.yearly.configuredTrialDays, 7)
    }

    func testProductionCatalogLoadsBothProducts() async {
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

        XCTAssertEqual(store.productLoadState, .loaded)
        XCTAssertEqual(store.products.count, SubscriptionPlan.allCases.count)
    }

    func testLoadProductsMapsEveryPlan() async {
        let client = MockStoreKitClient(
            products: [
                StorefrontProduct(id: "test.alike.monthly", displayName: "Monthly", displayPrice: "$6.99"),
                StorefrontProduct(id: "test.alike.yearly", displayName: "Yearly", displayPrice: "$39.99")
            ]
        )
        let store = makeStore(client: client)

        await store.loadProducts()

        XCTAssertEqual(store.productLoadState, .loaded)
        XCTAssertEqual(store.products[.monthly]?.displayPrice, "$6.99")
        XCTAssertEqual(store.products[.yearly]?.plan, .yearly)
    }

    func testRefreshGrantsAccessForVerifiedActiveEntitlement() async {
        let client = MockStoreKitClient(entitlements: [
            entitlement(productID: "test.alike.yearly", expirationDate: .distantFuture)
        ])
        let store = makeStore(client: client)

        await store.refreshEntitlements()

        XCTAssertTrue(store.entitlementState.isPremium)
        XCTAssertEqual(store.entitlementState.source, .verified)
        XCTAssertTrue(store.hasAccess(to: .screenshotCleanup))
        XCTAssertTrue(store.hasAccess(to: .cleanupReminders))
    }

    func testRefreshRejectsExpiredRevokedAndUnverifiedEntitlements() async {
        let client = MockStoreKitClient(entitlements: [
            entitlement(productID: "test.alike.monthly", expirationDate: .distantPast),
            entitlement(productID: "test.alike.yearly", expirationDate: .distantFuture, revocationDate: Date()),
            entitlement(productID: "test.alike.yearly", expirationDate: .distantFuture, isVerified: false)
        ])
        let store = makeStore(client: client)

        await store.refreshEntitlements()

        XCTAssertFalse(store.entitlementState.isPremium)
        XCTAssertFalse(store.hasAccess(to: .blurredPhotoCleanup))
    }

    func testPurchaseUsesVerifiedPayloadWhenCurrentEntitlementsAreEmpty() async throws {
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

        XCTAssertEqual(outcome, .purchased)
        XCTAssertTrue(store.entitlementState.isPremium)
        XCTAssertEqual(store.entitlementState.productID, "test.alike.yearly")
        XCTAssertEqual(client.purchasedProductID, "test.alike.yearly")
    }

    func testCachedAccessReconcilesBeforeSuspendedProductLoad() async throws {
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

        XCTAssertFalse(store.entitlementState.isPremium)
        XCTAssertEqual(store.entitlementState.source, .verified)

        await productRequests.resumeRequest(at: 0, returning: storefrontProducts())
        await startTask.value
    }

    func testFailedReloadClearsPreviouslyLoadedProducts() async {
        let client = MockStoreKitClient(products: storefrontProducts())
        let store = makeStore(client: client)
        await store.loadProducts()
        XCTAssertEqual(store.productLoadState, .loaded)

        client.products = [storefrontProducts()[0]]
        await store.loadProducts()

        XCTAssertTrue(store.products.isEmpty)
        guard case .failed = store.productLoadState else {
            return XCTFail("Expected the reload to fail")
        }
    }

    func testOlderRefreshCannotOverwriteNewerResult() async {
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

        XCTAssertTrue(store.entitlementState.isPremium)
        XCTAssertEqual(store.entitlementState.productID, "test.alike.yearly")
    }

    func testCancelledRefreshDoesNotOverwriteEntitlementState() async {
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

        XCTAssertTrue(store.entitlementState.isPremium)
        XCTAssertEqual(store.entitlementState.productID, "test.alike.monthly")
    }

    func testPurchaseAndRestoreSuccessClearEarlierErrors() async throws {
        let client = MockStoreKitClient(products: storefrontProducts())
        let store = makeStore(client: client)
        await store.loadProducts()

        client.purchaseError = TestFailure.expected
        do {
            _ = try await store.purchase(plan: .yearly)
            XCTFail("Expected purchase to fail")
        } catch {}
        XCTAssertNotNil(store.lastError)

        client.purchaseError = nil
        client.purchaseOutcome = .cancelled
        let retryOutcome = try await store.purchase(plan: .yearly)
        XCTAssertEqual(retryOutcome, .cancelled)
        XCTAssertNil(store.lastError)

        client.syncError = TestFailure.expected
        do {
            try await store.restorePurchases()
            XCTFail("Expected restore to fail")
        } catch {}
        XCTAssertNotNil(store.lastError)

        client.syncError = nil
        try await store.restorePurchases()
        XCTAssertNil(store.lastError)
    }

    func testRestoreSyncsThenRefreshesEntitlement() async throws {
        let client = MockStoreKitClient(entitlements: [
            entitlement(productID: "test.alike.monthly", expirationDate: .distantFuture)
        ])
        let store = makeStore(client: client)

        try await store.restorePurchases()

        XCTAssertTrue(client.didSync)
        XCTAssertTrue(store.entitlementState.isPremium)
    }

    func testExpiredCachedEntitlementDoesNotGrantAccessBeforeReconciliation() async throws {
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

        XCTAssertFalse(store.entitlementState.isPremium)
        XCTAssertEqual(store.entitlementState.source, .cached)
        XCTAssertNil(store.entitlementState.productID)
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
