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
        XCTAssertNil(SubscriptionPlan.monthly.trialDays)
        XCTAssertEqual(SubscriptionPlan.yearly.trialDays, 7)
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

    func testPurchaseRefreshesEntitlementAfterSuccess() async throws {
        let client = MockStoreKitClient(
            products: [
                StorefrontProduct(id: "test.alike.monthly", displayName: "Monthly", displayPrice: "$6.99"),
                StorefrontProduct(id: "test.alike.yearly", displayName: "Yearly", displayPrice: "$39.99")
            ],
            entitlements: [entitlement(productID: "test.alike.yearly", expirationDate: .distantFuture)],
            purchaseOutcome: .success(entitlement(productID: "test.alike.yearly", expirationDate: .distantFuture))
        )
        let store = makeStore(client: client)
        await store.loadProducts()

        let outcome = try await store.purchase(plan: .yearly)

        XCTAssertEqual(outcome, .purchased)
        XCTAssertTrue(store.entitlementState.isPremium)
        XCTAssertEqual(client.purchasedProductID, "test.alike.yearly")
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

    init(
        products: [StorefrontProduct] = [],
        entitlements: [StoreKitEntitlement] = [],
        purchaseOutcome: StoreKitPurchaseOutcome = .cancelled
    ) {
        self.products = products
        self.entitlements = entitlements
        self.purchaseOutcome = purchaseOutcome
    }

    func loadProducts(ids: Set<String>) async throws -> [StorefrontProduct] { products }

    func purchase(productID: String) async throws -> StoreKitPurchaseOutcome {
        purchasedProductID = productID
        return purchaseOutcome
    }

    func sync() async throws { didSync = true }

    func currentEntitlements() async -> [StoreKitEntitlement] { entitlements }

    func transactionUpdates() -> AsyncStream<StoreKitTransactionUpdate> {
        AsyncStream { $0.finish() }
    }
}
