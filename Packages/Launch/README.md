# Launch

The launch screen that shows while the app starts.

- **Category:** Feature (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Show the branded launch view.
- **Main public types:** `LaunchView`, `LaunchL10n`
- **Depends on:** DesignSystem
- **Does not do:** Load data, ask for permissions, or decide the first screen.
