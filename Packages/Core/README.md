# Core

The domain layer of Alike: models, repository protocols, and pure policies.
Every other app package depends on it, directly or through another package.
It also contains the Best Shot ranker, the premium access policy, and test mocks.

- **Category:** Foundation (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Define domain types, service and repository contracts, and decision logic without side effects.
- **Main public types:** `PhotoCluster`, `CleanupCategoryKind`, `BestShotRanker`, `PremiumAccessPolicy`, `PhotoClusterRepository`, `PhotoEnhancementService`
- **Depends on:** none
- **Does not do:** Implement PhotoKit, Vision, Core Data, or StoreKit work, or draw screens.
