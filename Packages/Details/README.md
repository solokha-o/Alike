# Details

The screens where the user reviews one cluster or one smart category.
In a cluster, the user compares similar photos, keeps the Best Shot, applies Enhance, and moves the rest to Recently Deleted.
The same tools work for the Screenshots and Blurred Photos categories.

- **Category:** Feature (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Show cluster and category review and apply the keep and move decisions of the user.
- **Main public types:** `ClusterDetailsView`, `ScreenshotCleanupView`, `DetailsL10n`
- **Depends on:** Core, DesignSystem, NavigationKit, Purchases, Storage
- **Does not do:** Find clusters, choose the review order, or delete photos without the system confirmation.
