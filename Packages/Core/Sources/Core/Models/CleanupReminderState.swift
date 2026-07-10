import Foundation

public enum CleanupReminderAuthorizationStatus: String, Equatable, Sendable, Codable {
    case notDetermined
    case denied
    case authorized
}

public struct CleanupReminderSchedule: Equatable, Sendable, Codable {
    public static let defaultWeekly = CleanupReminderSchedule(
        weekday: 1,
        hour: 18,
        minute: 0
    )

    public let weekday: Int
    public let hour: Int
    public let minute: Int

    public init(weekday: Int, hour: Int, minute: Int) {
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }
}

public struct CleanupReminderState: Equatable, Sendable, Codable {
    public let isEnabled: Bool
    public let authorizationStatus: CleanupReminderAuthorizationStatus
    public let schedule: CleanupReminderSchedule
    public let isScheduleCustomizationLocked: Bool

    public init(
        isEnabled: Bool,
        authorizationStatus: CleanupReminderAuthorizationStatus,
        schedule: CleanupReminderSchedule,
        isScheduleCustomizationLocked: Bool
    ) {
        self.isEnabled = isEnabled
        self.authorizationStatus = authorizationStatus
        self.schedule = schedule
        self.isScheduleCustomizationLocked = isScheduleCustomizationLocked
    }
}
