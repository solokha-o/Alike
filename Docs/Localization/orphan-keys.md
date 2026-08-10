# Orphan keys — deletion candidates

These keys live in the app catalog `Alike/Alike/Localizable.xcstrings` but appear in no
Swift source in this repository. The task 39 split left them in place rather than deleting
them, so the split diff carries no judgement calls. Each needs a look before it goes: a key
can be absent from source and still be live (assembled at runtime, or simply not wired up yet).

Both `en` and `uk` values are intact for all of them.

Count: 103

| Key | EN |
|---|---|
| `%d opportunities found • %@ estimated reclaimable` | %d opportunities found • %@ estimated reclaimable |
| `1 item • %@ estimated reclaimable` | 1 item • %@ estimated reclaimable |
| `10+ photos` | 10+ photos |
| `2+ photos` | 2+ photos |
| `20+ photos` | 20+ photos |
| `3+ photos` | 3+ photos |
| `5+ photos` | 5+ photos |
| `A weekly reminder appears every Sunday at 6:00 PM in your local time.` | A weekly reminder appears every Sunday at 6:00 PM in your local time. |
| `Advanced filters are a premium feature` | Advanced filters are a premium feature |
| `Alike could not complete the current operation` | Alike could not complete the current operation |
| `Alike needs access to your photo library to find similar photos. Please enable access in Settings.` | Alike needs access to your photo library to find similar photos. Please enable access in Settings. |
| `Analyzing Photos...` | Analyzing Photos... |
| `Batch cleanup is a premium feature` | Batch cleanup is a premium feature |
| `Browse groups of similar photos in a grid layout` | Browse groups of similar photos in a grid layout |
| `Button 1` | Button 1 |
| `Button 2` | Button 2 |
| `Button 3` | Button 3 |
| `Cleanup Categories` | Cleanup Categories |
| `Cleanup Review` | Cleanup Review |
| `Cleanup Session Progress` | Cleanup Session Progress |
| `Cleanup complete` | Cleanup complete |
| `Cleanup opportunities found` | Cleanup opportunities found |
| `Cleanup reminders are a premium feature` | Cleanup reminders are a premium feature |
| `Clear` | Clear |
| `Cluster review status` | Cluster review status |
| `Completed Cleanups` | Completed Cleanups |
| `Continue Cleanup` | Continue Cleanup |
| `Continue with Alike Free` | Continue with Alike Free |
| `Custom reminder schedule is a premium feature` | Custom reminder schedule is a premium feature |
| `Delete` | Delete |
| `Delete %d Selected Blurred Photos?` | Delete %d Selected Blurred Photos? |
| `Delete %d Selected Screenshots?` | Delete %d Selected Screenshots? |
| `Delete 1 Selected Blurred Photo?` | Delete 1 Selected Blurred Photo? |
| `Delete 1 Selected Photo?` | Delete 1 Selected Photo? |
| `Delete 1 Selected Screenshot?` | Delete 1 Selected Screenshot? |
| `Dismiss` | Dismiss |
| `Enable premium cleanup reminder access in debug builds` | Enable premium cleanup reminder access in debug builds |
| `Estimated Savings Reviewed So Far` | Estimated Savings Reviewed So Far |
| `Everything else that is still available in your cleanup queue` | Everything else that is still available in your cleanup queue |
| `Find duplicate and near-duplicate photos worth reviewing first.` | Find duplicate and near-duplicate photos worth reviewing first. |
| `Find similar photos and smart cleanup opportunities while keeping every decision in your control.` | Find similar photos and smart cleanup opportunities while keeping every decision in your control. |
| `Find visually similar photos in your library` | Find visually similar photos in your library |
| `Finding visually similar images` | Finding visually similar images |
| `Free includes %d scans per calendar month. You have %d remaining. Your allowance resets %@.` | Free includes %1$d scans per calendar month. You have %2$d remaining. Your allowance resets %3$@. |
| `Free includes 3 scans per calendar month. Unlock Premium for unlimited scans.` | Free includes 3 scans per calendar month. Unlock Premium for unlimited scans. |
| `Free up storage faster` | Free up storage faster |
| `Gallery changed since your last scan` | Gallery changed since your last scan |
| `Keep Best Only` | Keep Best Only |
| `Keep the best shot and select the rest for cleanup` | Keep the best shot and select the rest for cleanup |
| `Left to Review` | Left to Review |
| `Long-press a photo and choose 'Open Original' to view it full-screen` | Long-press a photo and choose 'Open Original' to view it full-screen |
| `New cluster found after the latest rescan` | New cluster found after the latest rescan |
| `No Similar Photos Found` | No Similar Photos Found |
| `No active controls` | No active controls |
| `Open Photo Details` | Open Photo Details |
| `Open cluster details to review and select photos` | Open cluster details to review and select photos |
| `Open premium details for weekly cleanup reminders` | Open premium details for weekly cleanup reminders |
| `Opens premium details for advanced filters` | Opens premium details for advanced filters |
| `Photo library access is needed to continue` | Photo library access is needed to continue |
| `Premium` | Premium |
| `Previously reviewed cluster changed and needs your review again` | Previously reviewed cluster changed and needs your review again |
| `Previously reviewed cluster with no significant changes` | Previously reviewed cluster with no significant changes |
| `Primary` | Primary |
| `Ready to Scan` | Ready to Scan |
| `Ready to scan your library` | Ready to scan your library |
| `Recently Deleted` | Recently Deleted |
| `Refreshing results from your photo library...` | Refreshing results from your photo library... |
| `Refreshing your cleanup results…` | Refreshing your cleanup results… |
| `Remove all currently selected photos` | Remove all currently selected photos |
| `Rescan Anytime` | Rescan Anytime |
| `Resets %@` | Resets %@ |
| `Reviewed Clusters: \(progress.reviewedCount) of \(progress.totalClusters)` | Reviewed Clusters: \(progress.reviewedCount) of \(progress.totalClusters) |
| `Run a rescan to refresh clusters and review the latest changes` | Run a rescan to refresh clusters and review the latest changes |
| `Save` | Save |
| `Secondary` | Secondary |
| `Select every photo except the best shot` | Select every photo except the best shot |
| `Selected to Review` | Selected to Review |
| `Starts scanning your photo library again` | Starts scanning your photo library again |
| `Tap the button below to analyze your photo library` | Tap the button below to analyze your photo library |
| `Tap the refresh button to rescan after adding new photos` | Tap the refresh button to rescan after adding new photos |
| `Test` | Test |
| `This moves the selected photo to Recently Deleted, including on devices using iCloud Photos. It can be recovered for 30 days. Estimated size: %@.` | This moves the selected photo to Recently Deleted, including on devices using iCloud Photos. It can be recovered for 30 days. Estimated size: %@. |
| `This moves the selected photos to Recently Deleted, including on devices using iCloud Photos. They can be recovered for 30 days. Estimated size: %@.` | This moves the selected photos to Recently Deleted, including on devices using iCloud Photos. They can be recovered for 30 days. Estimated size: %@. |
| `This moves the selected screenshot to Recently Deleted, including on devices using iCloud Photos. It can be recovered for 30 days. Estimated size: %@.` | This moves the selected screenshot to Recently Deleted, including on devices using iCloud Photos. It can be recovered for 30 days. Estimated size: %@. |
| `This moves the selected screenshots to Recently Deleted, including on devices using iCloud Photos. They can be recovered for 30 days. Estimated size: %@.` | This moves the selected screenshots to Recently Deleted, including on devices using iCloud Photos. They can be recovered for 30 days. Estimated size: %@. |
| `Total Clusters` | Total Clusters |
| `Total Selected Items` | Total Selected Items |
| `Try adjusting sensitivity in Settings` | Try adjusting sensitivity in Settings |
| `Try changing the filters or reset the controls` | Try changing the filters or reset the controls |
| `Unchanged` | Unchanged |
| `Unlimited rescans are a premium feature` | Unlimited rescans are a premium feature |
| `Unlimited scans are a premium feature` | Unlimited scans are a premium feature |
| `Unlock Cleanup Reminder Premium Feature` | Unlock Cleanup Reminder Premium Feature |
| `Unlock Unlimited Rescans Premium Feature` | Unlock Unlimited Rescans Premium Feature |
| `Unlock batch cleanup to remove multiple selected photos in one action.` | Unlock batch cleanup to remove multiple selected photos in one action. |
| `Unlock custom reminder timing to choose the day and time that fits your cleanup routine.` | Unlock custom reminder timing to choose the day and time that fits your cleanup routine. |
| `Unlock unlimited rescans to keep your cleanup results current as your library changes.` | Unlock unlimited rescans to keep your cleanup results current as your library changes. |
| `Unlock weekly cleanup reminders to come back to Alike, clear clutter, and keep saving storage over time.` | Unlock weekly cleanup reminders to come back to Alike, clear clutter, and keep saving storage over time. |
| `Your cleanup is ready` | Your cleanup is ready |
| `Your library is all caught up` | Your library is all caught up |
| `estimated` | estimated |
| `photos` | photos |
| `photos moved` | photos moved |
