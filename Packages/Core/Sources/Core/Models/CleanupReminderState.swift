import Foundation

public enum CleanupReminderAuthorizationStatus: String, Equatable, Sendable, Codable {
    case notDetermined
    case denied
    case authorized
}

public struct CleanupReminderState: Equatable, Sendable, Codable {
    public let isEnabled: Bool
    public let authorizationStatus: CleanupReminderAuthorizationStatus
    public let isLocked: Bool

    public init(
        isEnabled: Bool,
        authorizationStatus: CleanupReminderAuthorizationStatus,
        isLocked: Bool
    ) {
        self.isEnabled = isEnabled
        self.authorizationStatus = authorizationStatus
        self.isLocked = isLocked
    }
}
