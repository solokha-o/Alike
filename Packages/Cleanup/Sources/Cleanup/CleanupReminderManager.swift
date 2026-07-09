import Core
import Foundation
import UserNotifications

public actor CleanupReminderManager: CleanupReminderManaging {
    private enum ReminderSchedule {
        static let identifier = "cleanup.weekly.reminder"
        static let weekday = 1
        static let hour = 18
        static let minute = 0
    }

    private let preferenceRepository: CleanupReminderPreferenceRepository
    private let notificationCenter: any UserNotificationCenterControlling

    public init(preferenceRepository: CleanupReminderPreferenceRepository) {
        self.preferenceRepository = preferenceRepository
        self.notificationCenter = LiveUserNotificationCenter()
    }

    init(
        preferenceRepository: CleanupReminderPreferenceRepository,
        notificationCenter: any UserNotificationCenterControlling
    ) {
        self.preferenceRepository = preferenceRepository
        self.notificationCenter = notificationCenter
    }

    public func loadState(isPremiumUnlocked: Bool) async -> CleanupReminderState {
        let isReminderEnabled = await preferenceRepository.loadReminderEnabled()
        let authorizationStatus = await authorizationStatus()

        return CleanupReminderState(
            isEnabled: effectiveEnabled(
                storedPreference: isReminderEnabled,
                authorizationStatus: authorizationStatus,
                isPremiumUnlocked: isPremiumUnlocked
            ),
            authorizationStatus: authorizationStatus,
            isLocked: !isPremiumUnlocked
        )
    }

    public func setEnabled(_ isEnabled: Bool, isPremiumUnlocked: Bool) async -> CleanupReminderState {
        guard isPremiumUnlocked else {
            await removeScheduledReminder()
            return await loadState(isPremiumUnlocked: false)
        }

        guard isEnabled else {
            await preferenceRepository.saveReminderEnabled(false)
            await removeScheduledReminder()
            return await loadState(isPremiumUnlocked: true)
        }

        switch await authorizationStatus() {
        case .authorized:
            await preferenceRepository.saveReminderEnabled(true)
            await scheduleReminderIfPossible()
            return await loadState(isPremiumUnlocked: true)
        case .notDetermined:
            let granted = await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await preferenceRepository.saveReminderEnabled(true)
                await scheduleReminderIfPossible()
            } else {
                await preferenceRepository.saveReminderEnabled(false)
                await removeScheduledReminder()
            }
            return await loadState(isPremiumUnlocked: true)
        case .denied:
            await preferenceRepository.saveReminderEnabled(false)
            await removeScheduledReminder()
            return await loadState(isPremiumUnlocked: true)
        }
    }

    public func resync(isPremiumUnlocked: Bool) async {
        let isReminderEnabled = await preferenceRepository.loadReminderEnabled()

        guard isPremiumUnlocked else {
            await removeScheduledReminder()
            return
        }

        let authorizationStatus = await authorizationStatus()
        guard isReminderEnabled, authorizationStatus == .authorized else {
            await removeScheduledReminder()
            return
        }

        await scheduleReminderIfPossible()
    }
}

private extension CleanupReminderManager {
    func authorizationStatus() async -> CleanupReminderAuthorizationStatus {
        switch await notificationCenter.authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func effectiveEnabled(
        storedPreference: Bool,
        authorizationStatus: CleanupReminderAuthorizationStatus,
        isPremiumUnlocked: Bool
    ) -> Bool {
        storedPreference && authorizationStatus == .authorized && isPremiumUnlocked
    }

    func scheduleReminderIfPossible() async {
        await removeScheduledReminder()

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Ready for another cleanup?", bundle: .main)
        content.body = String(
            localized: "Open Alike this week to clear clutter and keep saving storage.",
            bundle: .main
        )
        content.sound = .default

        var components = DateComponents()
        components.weekday = ReminderSchedule.weekday
        components.hour = ReminderSchedule.hour
        components.minute = ReminderSchedule.minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: ReminderSchedule.identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to schedule cleanup reminder: \(error.localizedDescription)"))"
            )
        }
    }

    func removeScheduledReminder() async {
        await notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [ReminderSchedule.identifier]
        )
    }
}

protocol UserNotificationCenterControlling: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
}

private final class LiveUserNotificationCenter: @unchecked Sendable, UserNotificationCenterControlling {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: options) { isGranted, _ in
                continuation.resume(returning: isGranted)
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
