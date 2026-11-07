# Cleanup

The cleanup queue screen: the list of similar-photo clusters and the smart categories.
It sorts and filters clusters by review state, opens a cluster or a category, and shows cleanup history.
It also owns the weekly cleanup reminder and the rating prompt.

- **Category:** Feature (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Show what to review next and route the user to a cluster or a category.
- **Main public types:** `CleanupView`, `CleanupReviewFilter`, `CleanupClusterSort`, `CleanupReminderManager`, `RatingPromptCoordinator`, `CleanupWidgetEntry`
- **Depends on:** CleanupWorkspace, Core, DesignSystem, NavigationKit, PhotoAnalysis, Purchases, Storage
- **Does not do:** Run a scan, compare photos inside a cluster (Details), or persist data directly.
