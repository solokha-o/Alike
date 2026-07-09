import Foundation

#if DEBUG

public actor MockCleanupReminderPreferenceRepository: CleanupReminderPreferenceRepository {
    public var isReminderEnabled: Bool
    public var didCallLoadReminderEnabled = false
    public var didCallSaveReminderEnabled = false

    public init(isReminderEnabled: Bool = false) {
        self.isReminderEnabled = isReminderEnabled
    }

    public func loadReminderEnabled() async -> Bool {
        didCallLoadReminderEnabled = true
        return isReminderEnabled
    }

    public func saveReminderEnabled(_ isEnabled: Bool) async {
        didCallSaveReminderEnabled = true
        isReminderEnabled = isEnabled
    }
}

#endif
