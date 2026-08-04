public enum AppPreferenceKey {
    public static let sensitivity = "sensitivity"

    /// Column counts are stored per horizontal size class so a compact-width
    /// choice never overwrites the wider regular-width layout.
    public enum PhotoGrid {
        public static let compactColumns = "photoGrid.columns.compact"
        public static let regularColumns = "photoGrid.columns.regular"
    }

    public enum CleanupReminder {
        public static let isEnabled = "cleanup.reminder.isEnabled"
        public static let weekday = "cleanup.reminder.weekday"
        public static let hour = "cleanup.reminder.hour"
        public static let minute = "cleanup.reminder.minute"
    }

    public enum Premium {
        public static let monthlyScanUsage = "premium.monthlyScanUsage.v2"
        public static let legacyCompletedScanCount = "premium.completedScanCount.v1"
        public static let postFirstUsefulScanPrompt = "premium.prompt.postFirstUsefulScan.v1"
        public static let subscriptionEntitlement = "subscription.entitlement.v1"
    }

    /// Deliberately absent from `resettable`: deleting app data must not hand the user a
    /// fresh App Store review quota, matching how the premium prompt claim is treated.
    public enum Rating {
        public static let promptHistory = "rating.promptHistory.v1"
    }

    public enum DebugPremium {
        public static let unlimitedScans = "debug.premium.unlimitedRescans"
        public static let screenshotCleanup = "debug.premium.screenshotCleanup"
        public static let blurredPhotoCleanup = "debug.premium.blurredPhotoCleanup"
        public static let advancedFilters = "debug.premium.advancedFilters"
        public static let batchCleanup = "debug.premium.batchCleanup"
        public static let cleanupReminders = "debug.premium.cleanupReminders"
    }

    /// Retired in favour of `PhotoGrid`; still reset so existing installs do not
    /// keep a stale value in `UserDefaults` forever.
    private static let legacyGridColumns = "gridColumns"

    public static let resettable: [String] = [
        PhotoGrid.compactColumns,
        PhotoGrid.regularColumns,
        legacyGridColumns,
        sensitivity,
        CleanupReminder.isEnabled,
        CleanupReminder.weekday,
        CleanupReminder.hour,
        CleanupReminder.minute,
        DebugPremium.unlimitedScans,
        DebugPremium.screenshotCleanup,
        DebugPremium.blurredPhotoCleanup,
        DebugPremium.advancedFilters,
        DebugPremium.batchCleanup,
        DebugPremium.cleanupReminders
    ]
}
