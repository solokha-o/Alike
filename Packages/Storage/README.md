# Storage

The persistence layer: Core Data, files, and `UserDefaults`.
Each Core repository protocol has an implementation here. Most of them are actors.
It also detects photo library changes and deletes local app data.

- **Category:** Foundation (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Save and load clusters, scores, review state, history, and preferences.
- **Main public types:** `PersistenceController`, `CoreDataPhotoClusterRepository`, `FileClusterReviewStateRepository`, `UserDefaultsScanUsageRepository`, `PhotoKitChangeDetector`, `LocalAppDataDeletionService`
- **Depends on:** Core
- **Does not do:** Analyse photos, draw UI, or change the photo library.
