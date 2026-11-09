# CleanupWorkspace

The shared cleanup state that Scanner and Cleanup both read.
It runs scans, keeps the scan summary and progress, and reconciles stored clusters after a library change.
It also computes cleanup insights and history for the screens.

- **Category:** Foundation (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Own the cleanup session, the scan state, and the workspace content model.
- **Main public types:** `CleanupWorkspaceModel`, `CleanupSessionManager`, `CleanupWorkspaceContent`, `ScanOperationState`, `ScanSummary`, `CleanupInsightsService`
- **Depends on:** Core, PhotoAnalysis, Storage
- **Does not do:** Draw UI, talk to StoreKit, or write widget snapshots.
