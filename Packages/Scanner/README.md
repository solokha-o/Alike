# Scanner

The home screen: start a scan, follow its progress, and see the last scan result.
It shows the free scan allowance and the post-scan premium offer.

- **Category:** Feature (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Let the user start and follow a scan, then route to review.
- **Main public types:** `ScannerView`, `ScannerViewModel`, `PostScanPremiumOffer`, `ScannerL10n`
- **Depends on:** CleanupWorkspace, Core, DesignSystem, NavigationKit, Purchases, UserGuide
- **Does not do:** Run the analysis itself (CleanupWorkspace, PhotoAnalysis) or show clusters.
