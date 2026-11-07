# Purchases

Subscriptions through StoreKit 2, in two products.
`Purchases` loads products, buys, restores, and reports the premium entitlement.
`PurchasesUI` contains the paywall and the premium cards that features show.

- **Category:** Foundation; the `PurchasesUI` product is Foundation with UI (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Sell and verify the subscription and present premium offers.
- **Main public types:** `SubscriptionStore`, `SubscriptionCatalog`, `PurchaseOutcome`, `SubscriptionPaywallView`, `PremiumStatusCard`, `BatchCleanupUpsellCard`
- **Depends on:** Core, DesignSystem, NavigationKit
- **Does not do:** Decide which feature is premium (Core `PremiumAccessPolicy`) or count free scans (Storage).
