# Welcome

The first-run screens: what Alike does and the photo access request.
The same screens show again after the user deletes local app data.

- **Category:** Feature (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Introduce the app and get the photo library permission.
- **Main public types:** `WelcomeView`, `WelcomeViewModel`, `WelcomeMode`, `WelcomeL10n`
- **Depends on:** Core, DesignSystem, PhotoAnalysis
- **Does not do:** Start a scan or show a paywall.
