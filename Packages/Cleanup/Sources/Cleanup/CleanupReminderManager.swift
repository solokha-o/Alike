import Core
import Foundation
import UserNotifications

public actor CleanupReminderManager: CleanupReminderManaging {
    private enum ReminderSchedule {
        static let identifier = "cleanup.weekly.reminder"
    }

    private let preferenceRepository: CleanupReminderPreferenceRepository
    private let notificationCenter: any UserNotificationCenterControlling
    private let transactionGate = CleanupReminderTransactionGate()

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
        await transactionGate.acquire()
        let state = await loadStateWithinTransaction(isPremiumUnlocked: isPremiumUnlocked)
        await transactionGate.release()
        return state
    }

    public func setEnabled(
        _ isEnabled: Bool,
        isPremiumUnlocked: Bool
    ) async throws -> CleanupReminderState {
        await transactionGate.acquire()

        do {
            let state = try await setEnabledWithinTransaction(
                isEnabled,
                isPremiumUnlocked: isPremiumUnlocked
            )
            await transactionGate.release()
            return state
        } catch {
            await transactionGate.release()
            throw error
        }
    }

    public func setSchedule(
        _ schedule: CleanupReminderSchedule,
        isPremiumUnlocked: Bool
    ) async throws -> CleanupReminderState {
        await transactionGate.acquire()

        do {
            let state = try await setScheduleWithinTransaction(
                schedule,
                isPremiumUnlocked: isPremiumUnlocked
            )
            await transactionGate.release()
            return state
        } catch {
            await transactionGate.release()
            throw error
        }
    }

    public func resync(isPremiumUnlocked: Bool) async throws {
        await transactionGate.acquire()

        do {
            try await resyncWithinTransaction(isPremiumUnlocked: isPremiumUnlocked)
            await transactionGate.release()
        } catch {
            await transactionGate.release()
            throw error
        }
    }
}

private extension CleanupReminderManager {
    func loadStateWithinTransaction(isPremiumUnlocked: Bool) async -> CleanupReminderState {
        let isReminderEnabled = await preferenceRepository.loadReminderEnabled()
        let storedSchedule = await preferenceRepository.loadReminderSchedule()
        let authorizationStatus = await authorizationStatus()

        return CleanupReminderState(
            isEnabled: effectiveEnabled(
                storedPreference: isReminderEnabled,
                authorizationStatus: authorizationStatus
            ),
            authorizationStatus: authorizationStatus,
            schedule: effectiveSchedule(
                storedSchedule: storedSchedule,
                isPremiumUnlocked: isPremiumUnlocked
            ),
            isScheduleCustomizationLocked: !isPremiumUnlocked
        )
    }

    func setEnabledWithinTransaction(
        _ isEnabled: Bool,
        isPremiumUnlocked: Bool
    ) async throws -> CleanupReminderState {
        guard isEnabled else {
            await preferenceRepository.saveReminderEnabled(false)
            await removeScheduledReminder()
            return await loadStateWithinTransaction(isPremiumUnlocked: isPremiumUnlocked)
        }

        let schedule = await resolvedSchedule(isPremiumUnlocked: isPremiumUnlocked)
        switch await authorizationStatus() {
        case .authorized:
            try await scheduleReminder(schedule: schedule)
            await preferenceRepository.saveReminderEnabled(true)
            return await loadStateWithinTransaction(isPremiumUnlocked: isPremiumUnlocked)
        case .notDetermined:
            let granted = await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                try await scheduleReminder(schedule: schedule)
                await preferenceRepository.saveReminderEnabled(true)
            } else {
                await preferenceRepository.saveReminderEnabled(false)
                await removeScheduledReminder()
            }
            return await loadStateWithinTransaction(isPremiumUnlocked: isPremiumUnlocked)
        case .denied:
            await preferenceRepository.saveReminderEnabled(false)
            await removeScheduledReminder()
            return await loadStateWithinTransaction(isPremiumUnlocked: isPremiumUnlocked)
        }
    }

    func setScheduleWithinTransaction(
        _ schedule: CleanupReminderSchedule,
        isPremiumUnlocked: Bool
    ) async throws -> CleanupReminderState {
        guard isPremiumUnlocked else {
            return await loadStateWithinTransaction(isPremiumUnlocked: false)
        }

        let isReminderEnabled = await preferenceRepository.loadReminderEnabled()
        if isReminderEnabled, await authorizationStatus() == .authorized {
            try await scheduleReminder(schedule: schedule)
        }

        await preferenceRepository.saveReminderSchedule(schedule)
        return await loadStateWithinTransaction(isPremiumUnlocked: true)
    }

    func resyncWithinTransaction(isPremiumUnlocked: Bool) async throws {
        let isReminderEnabled = await preferenceRepository.loadReminderEnabled()

        let authorizationStatus = await authorizationStatus()
        guard isReminderEnabled, authorizationStatus == .authorized else {
            await removeScheduledReminder()
            return
        }

        let schedule = await resolvedSchedule(isPremiumUnlocked: isPremiumUnlocked)
        try await scheduleReminder(schedule: schedule)
    }

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
        authorizationStatus: CleanupReminderAuthorizationStatus
    ) -> Bool {
        storedPreference && authorizationStatus == .authorized
    }

    func effectiveSchedule(
        storedSchedule: CleanupReminderSchedule,
        isPremiumUnlocked: Bool
    ) -> CleanupReminderSchedule {
        isPremiumUnlocked ? storedSchedule : .defaultWeekly
    }

    func resolvedSchedule(isPremiumUnlocked: Bool) async -> CleanupReminderSchedule {
        let storedSchedule = await preferenceRepository.loadReminderSchedule()
        return effectiveSchedule(
            storedSchedule: storedSchedule,
            isPremiumUnlocked: isPremiumUnlocked
        )
    }

    func scheduleReminder(schedule: CleanupReminderSchedule) async throws {
        let request = CleanupReminderNotificationRequest(
            identifier: ReminderSchedule.identifier,
            title: String(localized: "Ready for another cleanup?", bundle: .main),
            body: String(
                localized: "Open Alike this week to clear clutter and keep saving storage.",
                bundle: .main
            ),
            schedule: schedule,
            repeats: true
        )
        try await notificationCenter.add(request)
    }

    func removeScheduledReminder() async {
        await notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [ReminderSchedule.identifier]
        )
    }
}

private actor CleanupReminderTransactionGate {
    private var isAcquired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isAcquired else {
            isAcquired = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            isAcquired = false
            return
        }

        waiters.removeFirst().resume()
    }
}

struct CleanupReminderNotificationRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let schedule: CleanupReminderSchedule
    let repeats: Bool
}

protocol UserNotificationCenterControlling: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool
    func add(_ request: CleanupReminderNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
}

private final class LiveUserNotificationCenter: @unchecked Sendable, UserNotificationCenterControlling {
    private var center: UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }

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

    func add(_ request: CleanupReminderNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default

        var components = DateComponents()
        components.weekday = request.schedule.weekday
        components.hour = request.schedule.hour
        components.minute = request.schedule.minute

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: request.repeats
        )
        let notificationRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(notificationRequest) { error in
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
