public enum AppPreferenceKey {
    public static let gridColumns = "gridColumns"
    public static let sensitivity = "sensitivity"

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

    public enum DebugPremium {
        public static let unlimitedScans = "debug.premium.unlimitedRescans"
        public static let screenshotCleanup = "debug.premium.screenshotCleanup"
        public static let blurredPhotoCleanup = "debug.premium.blurredPhotoCleanup"
        public static let advancedFilters = "debug.premium.advancedFilters"
        public static let batchCleanup = "debug.premium.batchCleanup"
        public static let cleanupReminders = "debug.premium.cleanupReminders"
    }

    public static let resettable: [String] = [
        gridColumns,
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
