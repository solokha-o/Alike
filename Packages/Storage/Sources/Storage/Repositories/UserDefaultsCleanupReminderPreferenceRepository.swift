import Core
import Foundation

/// UserDefaults-backed cleanup reminder preference repository.
public actor UserDefaultsCleanupReminderPreferenceRepository: CleanupReminderPreferenceRepository {
    private let userDefaults: UserDefaults
    private let reminderEnabledKey: String
    private let reminderWeekdayKey: String
    private let reminderHourKey: String
    private let reminderMinuteKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        reminderEnabledKey: String = "cleanup.reminder.isEnabled",
        reminderWeekdayKey: String = "cleanup.reminder.weekday",
        reminderHourKey: String = "cleanup.reminder.hour",
        reminderMinuteKey: String = "cleanup.reminder.minute"
    ) {
        self.userDefaults = userDefaults
        self.reminderEnabledKey = reminderEnabledKey
        self.reminderWeekdayKey = reminderWeekdayKey
        self.reminderHourKey = reminderHourKey
        self.reminderMinuteKey = reminderMinuteKey
    }

    public func loadReminderEnabled() async -> Bool {
        userDefaults.bool(forKey: reminderEnabledKey)
    }

    public func saveReminderEnabled(_ isEnabled: Bool) async {
        userDefaults.set(isEnabled, forKey: reminderEnabledKey)
    }

    public func loadReminderSchedule() async -> CleanupReminderSchedule {
        let defaultSchedule = CleanupReminderSchedule.defaultWeekly
        let weekday = validatedValue(
            forKey: reminderWeekdayKey,
            validRange: 1...7,
            fallback: defaultSchedule.weekday
        )
        let hour = validatedValue(
            forKey: reminderHourKey,
            validRange: 0...23,
            fallback: defaultSchedule.hour
        )
        let minute = validatedValue(
            forKey: reminderMinuteKey,
            validRange: 0...59,
            fallback: defaultSchedule.minute
        )

        return CleanupReminderSchedule(weekday: weekday, hour: hour, minute: minute)
    }

    public func saveReminderSchedule(_ schedule: CleanupReminderSchedule) async {
        userDefaults.set(schedule.weekday, forKey: reminderWeekdayKey)
        userDefaults.set(schedule.hour, forKey: reminderHourKey)
        userDefaults.set(schedule.minute, forKey: reminderMinuteKey)
    }
}

private extension UserDefaultsCleanupReminderPreferenceRepository {
    func validatedValue(
        forKey key: String,
        validRange: ClosedRange<Int>,
        fallback: Int
    ) -> Int {
        let storedValue = userDefaults.object(forKey: key) as? Int
        guard let storedValue, validRange.contains(storedValue) else {
            return fallback
        }

        return storedValue
    }
}
