import Foundation

#if DEBUG

public actor MockCleanupReminderPreferenceRepository: CleanupReminderPreferenceRepository {
    public var isReminderEnabled: Bool
    public var reminderSchedule: CleanupReminderSchedule
    public var didCallLoadReminderEnabled = false
    public var didCallSaveReminderEnabled = false
    public var didCallLoadReminderSchedule = false
    public var didCallSaveReminderSchedule = false

    public init(
        isReminderEnabled: Bool = false,
        reminderSchedule: CleanupReminderSchedule = .defaultWeekly
    ) {
        self.isReminderEnabled = isReminderEnabled
        self.reminderSchedule = reminderSchedule
    }

    public func loadReminderEnabled() async -> Bool {
        didCallLoadReminderEnabled = true
        return isReminderEnabled
    }

    public func saveReminderEnabled(_ isEnabled: Bool) async {
        didCallSaveReminderEnabled = true
        isReminderEnabled = isEnabled
    }

    public func loadReminderSchedule() async -> CleanupReminderSchedule {
        didCallLoadReminderSchedule = true
        return reminderSchedule
    }

    public func saveReminderSchedule(_ schedule: CleanupReminderSchedule) async {
        didCallSaveReminderSchedule = true
        reminderSchedule = schedule
    }
}

#endif
