# Glossary

This glossary gives one name for each domain concept in Alike.
Use the "Term in code" column in Swift and in technical documents.
Use the "Term in UI" column in user-facing text, release notes, and support replies.
The UI terms are the English values in the package string catalogs
(`Packages/*/Sources/*/Resources/Localizable.xcstrings`).

## Domain terms

| Concept | Term in code | Term in UI (en) | Definition |
|---|---|---|---|
| Cluster | `PhotoCluster`, `PhotoClusterSnapshot`, `PhotoClusterRepository` | "Similar Photos", "group", sometimes "cluster" | A set of 2 or more photos that look alike, found by one scan. |
| Similar photos | `PhotoClusteringService`, `VisionFeaturePrintService` | "Similar Photos" | The main category: clusters of photos that look alike, found with Vision feature prints. |
| Duplicates | no type; clusters cover them | "near-duplicates" (User Guide only) | Exact or near copies. Alike does not have a separate duplicates category. They appear inside clusters. |
| Best Shot | `PhotoClusterBestShot`, `BestShotRanker`, `BestShotDecision` | "Best Shot", "Make Best Shot" | The photo in a cluster that Alike suggests to keep. The user can choose a different one. |
| Keep | `ClusterReviewMode.keepBestOnly`, selection in `ClusterReviewState` | "Keep", "Keeping %1$d of %2$d" | A photo that the user does not select for cleanup stays in the library. |
| Review | `ClusterReviewState`, `ClusterReviewStatus` | "Review", "Needs review", "In review", "Reviewed" | The user opens a cluster, chooses what to keep, and marks the cluster as reviewed. |
| Re-review | `ClusterReviewStatus.needsReReview`, `ClusterResurfacingState` | "Needs review", "new" badge | A reviewed cluster that changed after a rescan and must be reviewed again. |
| Scan | `PhotoAnalysisService.analyzePhotoLibrary`, `ScanOperationState`, `ScanSummary` | "Scan", "Rescan", "Scan Again", "Last Scan" | One pass over the photo library that finds clusters and smart categories. |
| Cleanup | `CleanupSession`, `CleanupSessionManager`, `PhotoCleanupService` | "cleanup", "Review Cleanup" | The work of reviewing results and moving unwanted photos to Recently Deleted. |
| Cleanup history | `CleanupHistoryRepository`, `CleanupCompletionRecord` | "Photos Moved to Recently Deleted" | The record of photos that the user moved, with the date and the size. |
| Recently Deleted | `PhotoCleanupService.deleteAssets` | "Recently Deleted", "Move to Recently Deleted" | The Photos album that holds moved photos for 30 days. Alike never deletes a photo permanently. |
| Smart category | `CleanupCategoryKind`, `CleanupCategorySummary` | "smart category" | A list of photos with one property, outside clusters. The cases are `screenshots` and `blurredPhotos`. |
| Screenshots | `CleanupCategoryKind.screenshots`, `PremiumFeature.screenshotCleanup` | "Screenshots", "Screenshot Cleanup" | The smart category of screenshots. Bulk cleanup is a premium feature. |
| Blurred photos | `CleanupCategoryKind.blurredPhotos`, `PhotoQualityScore` | "Blurred Photos", "Blurred Photo Cleanup" | The smart category of photos with a low quality score. Bulk cleanup is a premium feature. |
| Enhance | `PhotoEnhancementService`, `PhotoKitEnhancementService`, `PhotoEnhancementState` | "Enhance", "Enhanced", "Revert to original" | An automatic edit of the kept photo. It is saved as a Photos edit that the user can revert. |
| Workspace | `CleanupWorkspaceModel`, `CleanupWorkspaceContent` | no UI term | The shared state of the current scan and cleanup that Scanner and Cleanup read. |
| Sensitivity | `SensitivityLevel` | "Sensitivity" | How alike photos must be to form a cluster. A change requires a new scan. |
| Personal weights | `BestShotPersonalWeights`, `PersonalWeightModel`, `BestShotPersonalizationRepository` | "Best Shot personalization", "Best Shot Learning", "Learning your taste" | Best Shot scoring weights that Alike adapts from the Best Shot choices of the user. |
| Calibration | `BestShotCalibration*`, package `BestShotCalibration` | no UI term (debug tool only) | Offline measurement of the Best Shot ranker on a labelled corpus. |
| Reclaimable estimate | `ReclaimableEstimate`, `ReclaimableEstimateCalculator` | "Estimated Savings", "Available to clean up" | The estimated storage that the user gets back after cleanup. |
| Free scan limit | `PremiumAccessPolicy.monthlyFreeScanLimit`, `MonthlyScanUsage`, `ScanUsageRepository` | "free scans remaining", "Monthly free-scan allowance" | The number of free scans each month (3). Premium removes the limit. |
| Premium | `PremiumAccessController`, `PremiumFeature`, `PremiumEntitlementState` | "Alike Pro", "Pro", sometimes "premium" | The subscription that unlocks unlimited scans, bulk cleanup of a smart category, batch cleanup, advanced filters, and a custom reminder. |
| Paywall | `SubscriptionPaywallView`, `PaywallPresentationState` | "Unlock …" titles, "premium paywall" (VoiceOver) | The screen that offers the subscription. |
| Cleanup reminder | `CleanupReminderManager`, `CleanupReminderSchedule` | "Weekly cleanup reminder", "Cleanup Reminder" | A weekly local notification that asks the user to continue cleanup. |
| Library change | `PhotoKitChangeDetector`, `PhotoLibraryChangeSummary` | "Library changed", "Scan New Photos" | Photos were added or removed after the last scan, so the results can be old. |
| Widget snapshot | `WidgetSnapshot`, `WidgetSnapshotStore` | no UI term | The data that the app writes to the App Group for the home and lock screen widgets. |
| Mascot reaction | `AlikeReactionCue`, `AlikeReactionView` | "Alike …" VoiceOver labels | The animated Alike character that reacts to the app state. |
| Crash report | `CrashReport`, `CrashReportStore` | crash report prompt | A MetricKit crash report kept on the device that the user can send by mail. |

## Mismatches between code and UI names

This list records the differences. Do not rename code or UI text because of this list.
A rename of a persisted value or a shipped string needs the change-safety gate first.

1. Cluster: the code always says `PhotoCluster`. The UI uses 3 words: "Similar Photos",
   "group" (User Guide, widget), and "cluster" (Cleanup, Details, Purchases).
2. Premium: the code says `Premium*`. The UI mostly says "Alike Pro" or "Pro", and some
   strings still say "premium".
3. Delete: the code says `deleteAssets`. The UI says "Move to Recently Deleted", because
   the photos stay in Recently Deleted for 30 days. "Delete" in the UI means Alike data only.
4. Blurred photos: the code says `blurredPhotos` and scores quality with
   `PhotoQualityScore`. The UI says "Blurred Photos", and the scanner subtitle says
   "Likely low-quality photos".
5. Personal weights: the code says personal weights and personalization. The UI says
   "Best Shot personalization", "Best Shot Learning", and "Learning your taste".
6. Free scan limit: the code says `monthlyFreeScanLimit`. The UI says "allowance".
7. Duplicates: there is no duplicates type in code. The User Guide says "near-duplicates".
8. Workspace and widget snapshot have no UI name.
9. Re-review: the code says `needsReReview`. The UI shows it as "Needs review", the same
   label as the "Needs review" section.
