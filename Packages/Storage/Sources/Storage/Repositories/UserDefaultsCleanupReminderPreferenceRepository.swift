import Core
import Foundation

/// UserDefaults-backed cleanup reminder preference repository.
public actor UserDefaultsCleanupReminderPreferenceRepository: CleanupReminderPreferenceRepository {
    private let userDefaults: UserDefaults
    private let reminderEnabledKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        reminderEnabledKey: String = "cleanup.reminder.isEnabled"
    ) {
        self.userDefaults = userDefaults
        self.reminderEnabledKey = reminderEnabledKey
    }

    public func loadReminderEnabled() async -> Bool {
        userDefaults.bool(forKey: reminderEnabledKey)
    }

    public func saveReminderEnabled(_ isEnabled: Bool) async {
        userDefaults.set(isEnabled, forKey: reminderEnabledKey)
    }
}
