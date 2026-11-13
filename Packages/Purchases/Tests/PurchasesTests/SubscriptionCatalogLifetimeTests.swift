import Core
import Foundation
import Testing
@testable import Purchases

/// The catalog evolution Experiment B depends on: more than one product ID per
/// plan, and a non-expiring lifetime product beside the plans.
@MainActor
struct SubscriptionCatalogLifetimeTests {
    /// The catalog shape Experiment B needs: an extra monthly ID and a lifetime product.
    private let catalog = SubscriptionCatalog(
        monthlyID: "test.alike.monthly",
        yearlyID: "test.alike.yearly",
        additionalProductIDs: [.monthly: ["test.alike.monthly.v0"]],
        lifetimeProductID: "test.alike.lifetime"
    )
    /// The catalog shape the shipped release has: two plans, nothing else.
    private let releaseCatalog = SubscriptionCatalog(
        monthlyID: "test.alike.monthly",
        yearlyID: "test.alike.yearly"
    )

    @Test func testProductionCatalogKnowsTheLifetimeProduct() {
        let catalog = SubscriptionCatalog.production

        #expect(catalog.lifetimeProductID == "com.alike.app.pro.lifetime")
        #expect(catalog.plan(for: "com.alike.app.pro.lifetime") == nil)
        #expect(catalog.grantsPremium(productID: "com.alike.app.pro.lifetime"))
        #expect(catalog.grantsPremium(productID: "com.alike.app.pro.monthly"))
        #expect(!catalog.grantsPremium(productID: "com.alike.app.pro.weekly"))
    }

    @Test func testAdditionalProductIDsMapToTheirPlanButAreNotSold() {
        #expect(catalog.plan(for: "test.alike.monthly.v0") == .monthly)
        #expect(catalog.productID(for: .monthly) == "test.alike.monthly")
        #expect(catalog.grantsPremium(productID: "test.alike.monthly.v0"))
        #expect(catalog.storefrontProductIDs == [
            "test.alike.monthly", "test.alike.yearly", "test.alike.lifetime",
        ])
        #expect(catalog.isConfigured)
    }

    /// Release behaviour: App Store Connect does not sell lifetime yet, so StoreKit
    /// returns only the two plans. They must still load.
    @Test func testMissingLifetimeProductDoesNotBlockThePlans() async {
        let client = MockStoreKitClient(products: storefrontProducts())
        let store = makeStore(client: client)

        await store.loadProducts()

        #expect(store.productLoadState == .loaded)
        #expect(store.products.count == SubscriptionPlan.allCases.count)
        #expect(store.lifetimeProduct == nil)
        #expect(client.requestedProductIDs == catalog.storefrontProductIDs)
    }

    @Test func testLoadProductsKeepsLifetimeApartFromThePlans() async {
        let client = MockStoreKitClient(products: storefrontProducts() + [
            StorefrontProduct(id: "test.alike.lifetime", displayName: "Lifetime", displayPrice: "$39.99"),
            StorefrontProduct(id: "test.alike.monthly.v0", displayName: "Old Monthly", displayPrice: "$4.99"),
        ])
        let store = makeStore(client: client)

        await store.loadProducts()

        #expect(store.productLoadState == .loaded)
        #expect(store.products[.monthly]?.id == "test.alike.monthly")
        #expect(store.products.count == SubscriptionPlan.allCases.count)
        #expect(store.lifetimeProduct?.id == "test.alike.lifetime")
        #expect(store.lifetimeProduct?.displayPrice == "$39.99")
    }

    @Test func testLifetimeAloneDoesNotLoadThePaywall() async {
        let client = MockStoreKitClient(products: [
            StorefrontProduct(id: "test.alike.lifetime", displayName: "Lifetime", displayPrice: "$39.99"),
        ])
        let store = makeStore(client: client)

        await store.loadProducts()

        #expect(store.lifetimeProduct == nil)
        guard case .failed = store.productLoadState else {
            Issue.record("Expected the load to fail without the plans")
            return
        }
    }

    @Test func testLifetimePurchaseGrantsPremiumWithoutExpiration() async throws {
        let client = MockStoreKitClient(
            products: storefrontProducts() + [
                StorefrontProduct(id: "test.alike.lifetime", displayName: "Lifetime", displayPrice: "$39.99"),
            ],
            purchaseOutcome: .success(entitlement(productID: "test.alike.lifetime", expirationDate: nil))
        )
        let store = makeStore(client: client)
        await store.loadProducts()

        let outcome = try await store.purchaseLifetime()

        #expect(outcome == .purchased)
        #expect(client.purchasedProductID == "test.alike.lifetime")
        #expect(store.entitlementState.isPremium)
        #expect(store.entitlementState.source == .verified)
        #expect(store.entitlementState.productID == "test.alike.lifetime")
        #expect(store.entitlementState.expirationDate == nil)
    }

    @Test func testLifetimePurchaseNeedsTheLoadedProduct() async {
        let client = MockStoreKitClient(products: storefrontProducts())
        let store = makeStore(client: client)
        await store.loadProducts()

        await #expect(throws: SubscriptionStoreError.self) { try await store.purchaseLifetime() }
        #expect(client.purchasedProductID == nil)
        #expect(!store.entitlementState.isPremium)
    }

    @Test func testLifetimePurchaseNeedsACatalogWithLifetime() async {
        let client = MockStoreKitClient(products: storefrontProducts())
        let store = makeStore(client: client)
        await store.loadProducts()

        await #expect(throws: SubscriptionStoreError.catalogNotConfigured) { try await store.purchaseLifetime() }
        #expect(client.purchasedProductID == nil)
    }

    @Test func testRestoreGrantsPremiumForLifetime() async throws {
        let client = MockStoreKitClient(entitlements: [
            entitlement(productID: "test.alike.lifetime", expirationDate: nil),
        ])
        let store = makeStore(client: client)

        try await store.restorePurchases()

        #expect(client.didSync)
        #expect(store.entitlementState.isPremium)
        #expect(store.entitlementState.productID == "test.alike.lifetime")
        #expect(store.entitlementState.expirationDate == nil)
    }

    /// The current release catalog has no lifetime: a lifetime transaction must not
    /// grant Premium there, exactly as any unknown product never did.
    @Test func testCatalogWithoutLifetimeIgnoresALifetimeTransaction() async {
        let client = MockStoreKitClient(entitlements: [
            entitlement(productID: "test.alike.lifetime", expirationDate: nil),
        ])
        let store = makeStore(client: client, catalog: releaseCatalog)

        await store.refreshEntitlements()

        #expect(!store.entitlementState.isPremium)
    }

    @Test func testAdditionalProductIDGrantsPremium() async {
        let client = MockStoreKitClient(entitlements: [
            entitlement(productID: "test.alike.monthly.v0", expirationDate: .distantFuture),
        ])
        let store = makeStore(client: client)

        await store.refreshEntitlements()

        #expect(store.entitlementState.isPremium)
        #expect(store.entitlementState.productID == "test.alike.monthly.v0")
    }

    @Test func testLifetimeOutranksAnActiveSubscription() async {
        let client = MockStoreKitClient(entitlements: [
            entitlement(productID: "test.alike.yearly", expirationDate: .distantFuture),
            entitlement(productID: "test.alike.lifetime", expirationDate: nil),
            entitlement(productID: "test.alike.monthly", expirationDate: Date().addingTimeInterval(3_600)),
        ])
        let store = makeStore(client: client)

        await store.refreshEntitlements()

        #expect(store.entitlementState.isPremium)
        #expect(store.entitlementState.productID == "test.alike.lifetime")
        #expect(store.entitlementState.expirationDate == nil)
    }

    @Test func testRefundedLifetimeRemovesPremium() async {
        let client = MockStoreKitClient(entitlements: [
            entitlement(productID: "test.alike.lifetime", expirationDate: nil),
        ])
        let store = makeStore(client: client)
        await store.refreshEntitlements()
        #expect(store.entitlementState.isPremium)

        client.entitlements = [
            entitlement(productID: "test.alike.lifetime", expirationDate: nil, revocationDate: Date()),
        ]
        await store.refreshEntitlements()

        #expect(!store.entitlementState.isPremium)
        #expect(store.entitlementState.productID == nil)
    }

    /// A cache written by the shipped release (a plan ID) and one written after a
    /// lifetime purchase (no expiration date) both read as Premium before StoreKit answers.
    @Test(arguments: [
        ("test.alike.monthly", Date.distantFuture as Date?),
        ("test.alike.lifetime", nil),
    ])
    func testCachedEntitlementReadsWithTheLifetimeCatalog(productID: String, expirationDate: Date?) async throws {
        let defaults = try #require(UserDefaults(suiteName: "PurchasesTests.\(UUID().uuidString)"))
        let cacheKey = UUID().uuidString
        let cached = PremiumEntitlementState(
            isPremium: true,
            source: .verified,
            productID: productID,
            expirationDate: expirationDate
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

        #expect(store.entitlementState.isPremium)
        #expect(store.entitlementState.source == .cached)
        #expect(store.entitlementState.productID == productID)
        #expect(store.entitlementState.expirationDate == expirationDate)

        await entitlementRequests.resumeRequest(
            at: 0,
            returning: [entitlement(productID: productID, expirationDate: expirationDate)]
        )
        await start.value

        #expect(store.entitlementState.isPremium)
        #expect(store.entitlementState.source == .verified)
    }

    private func makeStore(client: MockStoreKitClient, catalog: SubscriptionCatalog? = nil) -> SubscriptionStore {
        let defaults = UserDefaults(suiteName: "PurchasesTests.\(UUID().uuidString)")!
        return SubscriptionStore(
            catalog: catalog ?? self.catalog,
            client: client,
            defaults: defaults,
            cacheKey: UUID().uuidString
        )
    }

    private func storefrontProducts() -> [StorefrontProduct] {
        [
            StorefrontProduct(id: "test.alike.monthly", displayName: "Monthly", displayPrice: "$6.99"),
            StorefrontProduct(id: "test.alike.yearly", displayName: "Yearly", displayPrice: "$39.99"),
        ]
    }

    private func entitlement(
        productID: String,
        expirationDate: Date?,
        revocationDate: Date? = nil
    ) -> StoreKitEntitlement {
        StoreKitEntitlement(
            productID: productID,
            expirationDate: expirationDate,
            revocationDate: revocationDate,
            isUpgraded: false,
            isVerified: true
        )
    }
}
