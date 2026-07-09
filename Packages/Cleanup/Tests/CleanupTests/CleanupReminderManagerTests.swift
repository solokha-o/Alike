import Core
import Foundation
import UserNotifications
import XCTest
@testable import Cleanup

final class CleanupReminderManagerTests: XCTestCase {
    func testAuthorizedEnableSchedulesWeeklyReminder() async {
        let repository = MockCleanupReminderPreferenceRepository()
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let state = await manager.setEnabled(true, isPremiumUnlocked: true)

        let storedPreference = await repository.isReminderEnabled
        let scheduledRequest = await notificationCenter.addedRequests.last
        let removedIdentifiers = await notificationCenter.removedIdentifiers

        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.authorizationStatus, .authorized)
        XCTAssertFalse(state.isScheduleCustomizationLocked)
        XCTAssertTrue(storedPreference)
        XCTAssertEqual(removedIdentifiers, ["cleanup.weekly.reminder"])
        XCTAssertEqual(scheduledRequest?.identifier, "cleanup.weekly.reminder")

        let trigger = scheduledRequest?.trigger as? UNCalendarNotificationTrigger
        XCTAssertNotNil(trigger)
        XCTAssertEqual(trigger?.dateComponents.weekday, 1)
        XCTAssertEqual(trigger?.dateComponents.hour, 18)
        XCTAssertEqual(trigger?.dateComponents.minute, 0)
        XCTAssertEqual(trigger?.repeats, true)
    }

    func testAuthorizedEnableUsesStoredCustomScheduleWithPremiumAccess() async {
        let repository = MockCleanupReminderPreferenceRepository(
            reminderSchedule: CleanupReminderSchedule(weekday: 4, hour: 9, minute: 15)
        )
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let state = await manager.setEnabled(true, isPremiumUnlocked: true)
        let scheduledRequest = await notificationCenter.addedRequests.last
        let trigger = scheduledRequest?.trigger as? UNCalendarNotificationTrigger

        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.schedule, CleanupReminderSchedule(weekday: 4, hour: 9, minute: 15))
        XCTAssertEqual(trigger?.dateComponents.weekday, 4)
        XCTAssertEqual(trigger?.dateComponents.hour, 9)
        XCTAssertEqual(trigger?.dateComponents.minute, 15)
    }

    func testDisableRemovesReminderAndClearsPreference() async {
        let repository = MockCleanupReminderPreferenceRepository(isReminderEnabled: true)
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let state = await manager.setEnabled(false, isPremiumUnlocked: true)

        let storedPreference = await repository.isReminderEnabled
        let addedRequests = await notificationCenter.addedRequests
        let removedIdentifiers = await notificationCenter.removedIdentifiers

        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(storedPreference)
        XCTAssertTrue(addedRequests.isEmpty)
        XCTAssertEqual(removedIdentifiers, ["cleanup.weekly.reminder"])
    }

    func testNotDeterminedAuthorizationRequestsPermissionAndSchedulesWhenGranted() async {
        let repository = MockCleanupReminderPreferenceRepository()
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .notDetermined,
            requestAuthorizationResult: true,
            postRequestAuthorizationStatus: .authorized
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let state = await manager.setEnabled(true, isPremiumUnlocked: true)

        let didCallRequestAuthorization = await notificationCenter.didCallRequestAuthorization
        let addedRequests = await notificationCenter.addedRequests

        XCTAssertTrue(state.isEnabled)
        XCTAssertTrue(didCallRequestAuthorization)
        XCTAssertEqual(addedRequests.count, 1)
    }

    func testDeniedAuthorizationLeavesStateDisabledAndUnsheduled() async {
        let repository = MockCleanupReminderPreferenceRepository()
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .denied
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let state = await manager.setEnabled(true, isPremiumUnlocked: true)

        let storedPreference = await repository.isReminderEnabled
        let addedRequests = await notificationCenter.addedRequests

        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.authorizationStatus, .denied)
        XCTAssertFalse(storedPreference)
        XCTAssertTrue(addedRequests.isEmpty)
    }

    func testLoadStateFallsBackToDefaultScheduleWithoutPremiumAccess() async {
        let repository = MockCleanupReminderPreferenceRepository(
            isReminderEnabled: true,
            reminderSchedule: CleanupReminderSchedule(weekday: 6, hour: 7, minute: 45)
        )
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let state = await manager.loadState(isPremiumUnlocked: false)
        await manager.resync(isPremiumUnlocked: false)

        let scheduledRequest = await notificationCenter.addedRequests.last
        let trigger = scheduledRequest?.trigger as? UNCalendarNotificationTrigger

        XCTAssertTrue(state.isEnabled)
        XCTAssertTrue(state.isScheduleCustomizationLocked)
        XCTAssertEqual(state.schedule, .defaultWeekly)
        XCTAssertEqual(trigger?.dateComponents.weekday, 1)
        XCTAssertEqual(trigger?.dateComponents.hour, 18)
        XCTAssertEqual(trigger?.dateComponents.minute, 0)
    }

    func testResyncRestoresScheduleFromPersistedPreference() async {
        let repository = MockCleanupReminderPreferenceRepository(
            isReminderEnabled: true,
            reminderSchedule: CleanupReminderSchedule(weekday: 2, hour: 11, minute: 5)
        )
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        await manager.resync(isPremiumUnlocked: true)

        let addedRequests = await notificationCenter.addedRequests
        XCTAssertEqual(addedRequests.count, 1)
        XCTAssertEqual(addedRequests.first?.identifier, "cleanup.weekly.reminder")
        let trigger = addedRequests.first?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.weekday, 2)
        XCTAssertEqual(trigger?.dateComponents.hour, 11)
        XCTAssertEqual(trigger?.dateComponents.minute, 5)
    }

    func testSetSchedulePersistsCustomScheduleAndReschedulesWhenPremiumIsUnlocked() async {
        let repository = MockCleanupReminderPreferenceRepository(isReminderEnabled: true)
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )
        let customSchedule = CleanupReminderSchedule(weekday: 3, hour: 14, minute: 20)

        let state = await manager.setSchedule(customSchedule, isPremiumUnlocked: true)

        let storedSchedule = await repository.reminderSchedule
        let scheduledRequest = await notificationCenter.addedRequests.last
        let trigger = scheduledRequest?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(state.schedule, customSchedule)
        XCTAssertFalse(state.isScheduleCustomizationLocked)
        XCTAssertEqual(storedSchedule, customSchedule)
        XCTAssertEqual(trigger?.dateComponents.weekday, 3)
        XCTAssertEqual(trigger?.dateComponents.hour, 14)
        XCTAssertEqual(trigger?.dateComponents.minute, 20)
    }

    func testSetScheduleWithoutPremiumLeavesDefaultEffectiveSchedule() async {
        let repository = MockCleanupReminderPreferenceRepository(
            isReminderEnabled: true,
            reminderSchedule: CleanupReminderSchedule(weekday: 5, hour: 16, minute: 25)
        )
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let state = await manager.setSchedule(
            CleanupReminderSchedule(weekday: 2, hour: 8, minute: 10),
            isPremiumUnlocked: false
        )

        let storedSchedule = await repository.reminderSchedule
        let addedRequests = await notificationCenter.addedRequests
        XCTAssertEqual(state.schedule, .defaultWeekly)
        XCTAssertTrue(state.isScheduleCustomizationLocked)
        XCTAssertEqual(storedSchedule, CleanupReminderSchedule(weekday: 5, hour: 16, minute: 25))
        XCTAssertTrue(addedRequests.isEmpty)
    }
}

private actor MockUserNotificationCenter: UserNotificationCenterControlling {
    var authorizationStatus: UNAuthorizationStatus
    var requestAuthorizationResult: Bool
    var postRequestAuthorizationStatus: UNAuthorizationStatus
    var didCallRequestAuthorization = false
    var addedRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [String] = []

    init(
        authorizationStatus: UNAuthorizationStatus,
        requestAuthorizationResult: Bool = false,
        postRequestAuthorizationStatus: UNAuthorizationStatus? = nil
    ) {
        self.authorizationStatus = authorizationStatus
        self.requestAuthorizationResult = requestAuthorizationResult
        self.postRequestAuthorizationStatus = postRequestAuthorizationStatus ?? authorizationStatus
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool {
        didCallRequestAuthorization = true
        authorizationStatus = postRequestAuthorizationStatus
        return requestAuthorizationResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        removedIdentifiers.append(contentsOf: identifiers)
    }
}
