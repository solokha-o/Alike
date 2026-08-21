# Orphan keys — deleted in task 40

Task 39 split the catalogs and left 103 keys in the app catalog that appeared in no Swift
source, listing them here rather than deleting them, so its diff carried no judgement calls.
Task 40 made the call: at five new languages they were roughly 500 strings of translation for
copy that renders nowhere.

**They are gone.** This file is now the record of that deletion, not a to-do list.

## What went

106 keys were deleted from `Alike/Alike/Localizable.xcstrings`: the 103 listed by task 39,
plus three more that the task 39 list had missed —
`Primary Button` and `Secondary Button`, extracted out of a `#Preview` in
`DesignSystem/Components/Buttons.swift`, and a bare `Storage` with no call site at all.

Both `en` and `uk` values were intact for every one of them. Nothing was translated first.

One more went later, for a different reason: `welcome.main.grantAccess` in the Welcome catalog.
App Review rejected the build under guideline 5.1.1(iv) because a "Grant Access" button in front
of the system photo prompt steers the answer, so the onboarding CTA now resolves
`welcome.main.continue` in every mode and the old key had no call site left.

## What stayed

Four keys in the app catalog were live all along — the rescan alert in `Alike/Alike/Router/RootView.swift`.
They were literal English strings acting as their own keys; they now carry semantic names
(`alike.rescan.title`, `.later`, `.now`, `.message`) and resolve through `AlikeL10n`, like every
package string resolves through its own `<Pkg>L10n`. The renames are in `key-migration.csv`.

The app catalog is now 7 keys: those four plus the three tab titles.

## Recovering one

Every deleted value is in git. To bring a key back, take it from the commit before the deletion:

```bash
git log --oneline -- Alike/Alike/Localizable.xcstrings
git show <commit-before>:Alike/Alike/Localizable.xcstrings
```

A key that comes back should come back with a semantic name and a call site, not as a literal.

## Deleted keys

| Key |
|---|
| `%d opportunities found • %@ estimated reclaimable` |
| `1 item • %@ estimated reclaimable` |
| `10+ photos` |
| `2+ photos` |
| `20+ photos` |
| `3+ photos` |
| `5+ photos` |
| `A weekly reminder appears every Sunday at 6:00 PM in your local time.` |
| `Advanced filters are a premium feature` |
| `Alike could not complete the current operation` |
| `Alike needs access to your photo library to find similar photos. Please enable access in Settings.` |
| `Analyzing Photos...` |
| `Batch cleanup is a premium feature` |
| `Browse groups of similar photos in a grid layout` |
| `Button 1` |
| `Button 2` |
| `Button 3` |
| `Cleanup Categories` |
| `Cleanup Review` |
| `Cleanup Session Progress` |
| `Cleanup complete` |
| `Cleanup opportunities found` |
| `Cleanup reminders are a premium feature` |
| `Clear` |
| `Cluster review status` |
| `Completed Cleanups` |
| `Continue Cleanup` |
| `Continue with Alike Free` |
| `Custom reminder schedule is a premium feature` |
| `Delete` |
| `Delete %d Selected Blurred Photos?` |
| `Delete %d Selected Screenshots?` |
| `Delete 1 Selected Blurred Photo?` |
| `Delete 1 Selected Photo?` |
| `Delete 1 Selected Screenshot?` |
| `Dismiss` |
| `Enable premium cleanup reminder access in debug builds` |
| `Estimated Savings Reviewed So Far` |
| `Everything else that is still available in your cleanup queue` |
| `Find duplicate and near-duplicate photos worth reviewing first.` |
| `Find similar photos and smart cleanup opportunities while keeping every decision in your control.` |
| `Find visually similar photos in your library` |
| `Finding visually similar images` |
| `Free includes %d scans per calendar month. You have %d remaining. Your allowance resets %@.` |
| `Free includes 3 scans per calendar month. Unlock Premium for unlimited scans.` |
| `Free up storage faster` |
| `Gallery changed since your last scan` |
| `Keep Best Only` |
| `Keep the best shot and select the rest for cleanup` |
| `Left to Review` |
| `Long-press a photo and choose 'Open Original' to view it full-screen` |
| `New cluster found after the latest rescan` |
| `No Similar Photos Found` |
| `No active controls` |
| `Open Photo Details` |
| `Open cluster details to review and select photos` |
| `Open premium details for weekly cleanup reminders` |
| `Opens premium details for advanced filters` |
| `Photo library access is needed to continue` |
| `Premium` |
| `Previously reviewed cluster changed and needs your review again` |
| `Previously reviewed cluster with no significant changes` |
| `Primary` |
| `Primary Button` |
| `Ready to Scan` |
| `Ready to scan your library` |
| `Recently Deleted` |
| `Refreshing results from your photo library...` |
| `Refreshing your cleanup results…` |
| `Remove all currently selected photos` |
| `Rescan Anytime` |
| `Resets %@` |
| `Reviewed Clusters: \(progress.reviewedCount) of \(progress.totalClusters)` |
| `Run a rescan to refresh clusters and review the latest changes` |
| `Save` |
| `Secondary` |
| `Secondary Button` |
| `Select every photo except the best shot` |
| `Selected to Review` |
| `Starts scanning your photo library again` |
| `Storage` |
| `Tap the button below to analyze your photo library` |
| `Tap the refresh button to rescan after adding new photos` |
| `Test` |
| `This moves the selected photo to Recently Deleted, including on devices using iCloud Photos. It can be recovered for 30 days. Estimated size: %@.` |
| `This moves the selected photos to Recently Deleted, including on devices using iCloud Photos. They can be recovered for 30 days. Estimated size: %@.` |
| `This moves the selected screenshot to Recently Deleted, including on devices using iCloud Photos. It can be recovered for 30 days. Estimated size: %@.` |
| `This moves the selected screenshots to Recently Deleted, including on devices using iCloud Photos. They can be recovered for 30 days. Estimated size: %@.` |
| `Total Clusters` |
| `Total Selected Items` |
| `Try adjusting sensitivity in Settings` |
| `Try changing the filters or reset the controls` |
| `Unchanged` |
| `Unlimited rescans are a premium feature` |
| `Unlimited scans are a premium feature` |
| `Unlock Cleanup Reminder Premium Feature` |
| `Unlock Unlimited Rescans Premium Feature` |
| `Unlock batch cleanup to remove multiple selected photos in one action.` |
| `Unlock custom reminder timing to choose the day and time that fits your cleanup routine.` |
| `Unlock unlimited rescans to keep your cleanup results current as your library changes.` |
| `Unlock weekly cleanup reminders to come back to Alike, clear clutter, and keep saving storage over time.` |
| `Your cleanup is ready` |
| `Your library is all caught up` |
| `estimated` |
| `photos` |
| `photos moved` |
