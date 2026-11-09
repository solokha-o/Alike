# PhotoAnalysis

The PhotoKit and Vision implementations of the Core service protocols.
It finds clusters of similar photos with feature prints, scores photo quality, moves photos to Recently Deleted, and renders Enhance edits.
It also wraps the photo library permission.

- **Category:** Foundation (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Read and change the photo library and analyse photos on the device.
- **Main public types:** `PhotoAnalysisServiceImpl`, `PhotoClusteringService`, `VisionFeaturePrintService`, `PhotoKitCleanupService`, `PhotoKitEnhancementService`, `PhotoPermissionManagerImpl`
- **Depends on:** Core
- **Does not do:** Persist results (Storage), draw UI, or send photos off the device.
