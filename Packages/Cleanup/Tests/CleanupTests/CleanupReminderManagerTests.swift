import Core
import UserNotifications
import Foundation
import Testing
@testable import Cleanup

@Suite struct CleanupReminderManagerTests {
    @Test func testAuthorizedEnableSchedulesWeeklyReminder() async throws {
        let repository = MockCleanupReminderPreferenceRepository()
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let state = try await manager.setEnabled(true, isPremiumUnlocked: true)

        let storedPreference = await repository.isReminderEnabled
        let scheduledRequest = await notificationCenter.addedRequests.last
        let removedIdentifiers = await notificationCenter.removedIdentifiers

        #expect(state.isEnabled)
        #expect(state.authorizationStatus == .authorized)
        #expect(!state.isScheduleCustomizationLocked)
        #expect(storedPreference)
        #expect(removedIdentifiers.isEmpty)
        #expect(scheduledRequest?.identifier == "cleanup.weekly.reminder")
        #expect(scheduledRequest?.schedule == .defaultWeekly)
        #expect(scheduledRequest?.repeats == true)
    }

    @Test func testAuthorizedEnableUsesStoredCustomScheduleWithPremiumAccess() async throws {
        let customSchedule = CleanupReminderSchedule(weekday: 4, hour: 9, minute: 15)
        let repository = MockCleanupReminderPreferenceRepository(
            reminderSchedule: customSchedule
        )
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let state = try await manager.setEnabled(true, isPremiumUnlocked: true)
        let scheduledRequest = await notificationCenter.addedRequests.last

        #expect(state.isEnabled)
        #expect(state.schedule == customSchedule)
        #expect(scheduledRequest?.schedule == customSchedule)
    }

    @Test func testEnablePropagatesAddFailureAndKeepsPreferenceDisabled() async {
        let repository = MockCleanupReminderPreferenceRepository()
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized,
            shouldFailAdd: true
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        do {
            _ = try await manager.setEnabled(true, isPremiumUnlocked: true)
            Issue.record("Expected notification scheduling to fail")
        } catch {
            #expect(error as? TestNotificationCenterError == .addFailed)
        }

        let state = await manager.loadState(isPremiumUnlocked: true)
        let storedPreference = await repository.isReminderEnabled
        let addAttemptCount = await notificationCenter.addAttemptCount
        let removedIdentifiers = await notificationCenter.removedIdentifiers
        #expect(!state.isEnabled)
        #expect(!storedPreference)
        #expect(addAttemptCount == 1)
        #expect(removedIdentifiers.isEmpty)
    }

    @Test func testDisableRemovesReminderAndClearsPreference() async throws {
        let existingRequest = makeReminderRequest(schedule: .defaultWeekly)
        let repository = MockCleanupReminderPreferenceRepository(isReminderEnabled: true)
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized,
            pendingRequests: [existingRequest]
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let state = try await manager.setEnabled(false, isPremiumUnlocked: true)

        let storedPreference = await repository.isReminderEnabled
        let pendingRequests = await notificationCenter.pendingRequests
        let removedIdentifiers = await notificationCenter.removedIdentifiers

        #expect(!state.isEnabled)
        #expect(!storedPreference)
        #expect(pendingRequests.isEmpty)
        #expect(removedIdentifiers == ["cleanup.weekly.reminder"])
    }

    @Test func testNotDeterminedAuthorizationRequestsPermissionAndSchedulesWhenGranted() async throws {
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

        let state = try await manager.setEnabled(true, isPremiumUnlocked: true)

        let didCallRequestAuthorization = await notificationCenter.didCallRequestAuthorization
        let addedRequests = await notificationCenter.addedRequests

        #expect(state.isEnabled)
        #expect(didCallRequestAuthorization)
        #expect(addedRequests.count == 1)
    }

    @Test func testDeniedAuthorizationLeavesStateDisabledAndUnscheduled() async throws {
        let repository = MockCleanupReminderPreferenceRepository()
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .denied
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let state = try await manager.setEnabled(true, isPremiumUnlocked: true)

        let storedPreference = await repository.isReminderEnabled
        let addedRequests = await notificationCenter.addedRequests

        #expect(!state.isEnabled)
        #expect(state.authorizationStatus == .denied)
        #expect(!storedPreference)
        #expect(addedRequests.isEmpty)
    }

    @Test func testLoadStateFallsBackToDefaultScheduleWithoutPremiumAccess() async throws {
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
        try await manager.resync(isPremiumUnlocked: false)

        let scheduledRequest = await notificationCenter.addedRequests.last

        #expect(state.isEnabled)
        #expect(state.isScheduleCustomizationLocked)
        #expect(state.schedule == .defaultWeekly)
        #expect(scheduledRequest?.schedule == .defaultWeekly)
    }

    @Test func testResyncRestoresScheduleFromPersistedPreference() async throws {
        let storedSchedule = CleanupReminderSchedule(weekday: 2, hour: 11, minute: 5)
        let repository = MockCleanupReminderPreferenceRepository(
            isReminderEnabled: true,
            reminderSchedule: storedSchedule
        )
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        try await manager.resync(isPremiumUnlocked: true)

        let addedRequests = await notificationCenter.addedRequests
        #expect(addedRequests.count == 1)
        #expect(addedRequests.first?.identifier == "cleanup.weekly.reminder")
        #expect(addedRequests.first?.schedule == storedSchedule)
    }

    /// A relaunch builds a new manager over the same stored preference; the reminder
    /// the user enabled before must still read as enabled, with the same schedule.
    @Test func testNewManagerOverPersistedPreferenceLoadsEnabledState() async throws {
        let customSchedule = CleanupReminderSchedule(weekday: 3, hour: 20, minute: 30)
        let repository = MockCleanupReminderPreferenceRepository(
            reminderSchedule: customSchedule
        )
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized
        )
        let firstLaunchManager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )
        _ = try await firstLaunchManager.setEnabled(true, isPremiumUnlocked: true)

        let relaunchedManager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )
        let state = await relaunchedManager.loadState(isPremiumUnlocked: true)
        try await relaunchedManager.resync(isPremiumUnlocked: true)

        let addedRequests = await notificationCenter.addedRequests
        #expect(state.isEnabled)
        #expect(state.schedule == customSchedule)
        #expect(Set(addedRequests.map(\.identifier)) == ["cleanup.weekly.reminder"])
    }

    @Test func testResyncPropagatesAddFailureWithoutRemovingExistingRequest() async {
        let storedSchedule = CleanupReminderSchedule(weekday: 2, hour: 11, minute: 5)
        let existingRequest = makeReminderRequest(schedule: .defaultWeekly)
        let repository = MockCleanupReminderPreferenceRepository(
            isReminderEnabled: true,
            reminderSchedule: storedSchedule
        )
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized,
            shouldFailAdd: true,
            pendingRequests: [existingRequest]
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        do {
            try await manager.resync(isPremiumUnlocked: true)
            Issue.record("Expected reminder resync to fail")
        } catch {
            #expect(error as? TestNotificationCenterError == .addFailed)
        }

        let pendingRequest = await notificationCenter.pendingRequests[existingRequest.identifier]
        let removedIdentifiers = await notificationCenter.removedIdentifiers
        #expect(pendingRequest == existingRequest)
        #expect(removedIdentifiers.isEmpty)
    }

    @Test func testSetScheduleReplacesExistingRequestWithoutPreRemoval() async throws {
        let oldSchedule = CleanupReminderSchedule(weekday: 2, hour: 9, minute: 0)
        let newSchedule = CleanupReminderSchedule(weekday: 3, hour: 14, minute: 20)
        let existingRequest = makeReminderRequest(schedule: oldSchedule)
        let repository = MockCleanupReminderPreferenceRepository(
            isReminderEnabled: true,
            reminderSchedule: oldSchedule
        )
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized,
            pendingRequests: [existingRequest]
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let state = try await manager.setSchedule(newSchedule, isPremiumUnlocked: true)

        let storedSchedule = await repository.reminderSchedule
        let pendingRequest = await notificationCenter.pendingRequests[existingRequest.identifier]
        let removedIdentifiers = await notificationCenter.removedIdentifiers
        #expect(state.schedule == newSchedule)
        #expect(storedSchedule == newSchedule)
        #expect(pendingRequest?.schedule == newSchedule)
        #expect(removedIdentifiers.isEmpty)
    }

    @Test func testSetScheduleFailurePreservesStoredScheduleAndExistingRequest() async {
        let oldSchedule = CleanupReminderSchedule(weekday: 2, hour: 9, minute: 0)
        let newSchedule = CleanupReminderSchedule(weekday: 3, hour: 14, minute: 20)
        let existingRequest = makeReminderRequest(schedule: oldSchedule)
        let repository = MockCleanupReminderPreferenceRepository(
            isReminderEnabled: true,
            reminderSchedule: oldSchedule
        )
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized,
            shouldFailAdd: true,
            pendingRequests: [existingRequest]
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        do {
            _ = try await manager.setSchedule(newSchedule, isPremiumUnlocked: true)
            Issue.record("Expected reminder replacement to fail")
        } catch {
            #expect(error as? TestNotificationCenterError == .addFailed)
        }

        let state = await manager.loadState(isPremiumUnlocked: true)
        let storedSchedule = await repository.reminderSchedule
        let pendingRequest = await notificationCenter.pendingRequests[existingRequest.identifier]
        let removedIdentifiers = await notificationCenter.removedIdentifiers
        #expect(state.schedule == oldSchedule)
        #expect(storedSchedule == oldSchedule)
        #expect(pendingRequest == existingRequest)
        #expect(removedIdentifiers.isEmpty)
    }

    @Test func testSetScheduleWithoutPremiumLeavesDefaultEffectiveSchedule() async throws {
        let storedSchedule = CleanupReminderSchedule(weekday: 5, hour: 16, minute: 25)
        let repository = MockCleanupReminderPreferenceRepository(
            isReminderEnabled: true,
            reminderSchedule: storedSchedule
        )
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let state = try await manager.setSchedule(
            CleanupReminderSchedule(weekday: 2, hour: 8, minute: 10),
            isPremiumUnlocked: false
        )

        let persistedSchedule = await repository.reminderSchedule
        let addedRequests = await notificationCenter.addedRequests
        #expect(state.schedule == .defaultWeekly)
        #expect(state.isScheduleCustomizationLocked)
        #expect(persistedSchedule == storedSchedule)
        #expect(addedRequests.isEmpty)
    }

    @Test func testConcurrentResyncWaitsForScheduleTransactionAndUsesLatestSchedule() async throws {
        let oldSchedule = CleanupReminderSchedule(weekday: 2, hour: 9, minute: 0)
        let latestSchedule = CleanupReminderSchedule(weekday: 6, hour: 17, minute: 35)
        let repository = MockCleanupReminderPreferenceRepository(
            isReminderEnabled: true,
            reminderSchedule: oldSchedule
        )
        let notificationCenter = MockUserNotificationCenter(
            authorizationStatus: .authorized,
            shouldSuspendNextAdd: true
        )
        let manager = CleanupReminderManager(
            preferenceRepository: repository,
            notificationCenter: notificationCenter
        )

        let updateTask = Task {
            try await manager.setSchedule(latestSchedule, isPremiumUnlocked: true)
        }
        await notificationCenter.waitUntilAddIsSuspended()

        let resyncTask = Task {
            try await manager.resync(isPremiumUnlocked: true)
        }
        await Task.yield()
        await notificationCenter.resumeSuspendedAdd()

        _ = try await updateTask.value
        try await resyncTask.value

        let persistedSchedule = await repository.reminderSchedule
        let addedSchedules = await notificationCenter.addedRequests.map(\.schedule)
        let pendingRequest = await notificationCenter.pendingRequests["cleanup.weekly.reminder"]
        #expect(persistedSchedule == latestSchedule)
        #expect(addedSchedules == [latestSchedule, latestSchedule])
        #expect(pendingRequest?.schedule == latestSchedule)
    }
}

private enum TestNotificationCenterError: Error, Equatable, Sendable {
    case addFailed
}

private actor MockUserNotificationCenter: UserNotificationCenterControlling {
    var authorizationStatus: UNAuthorizationStatus
    var requestAuthorizationResult: Bool
    var postRequestAuthorizationStatus: UNAuthorizationStatus
    var shouldFailAdd: Bool
    var shouldSuspendNextAdd: Bool
    var didCallRequestAuthorization = false
    var addAttemptCount = 0
    var addedRequests: [CleanupReminderNotificationRequest] = []
    var pendingRequests: [String: CleanupReminderNotificationRequest]
    var removedIdentifiers: [String] = []
    private var suspendedAddContinuation: CheckedContinuation<Void, Never>?
    private var suspendedAddWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        authorizationStatus: UNAuthorizationStatus,
        requestAuthorizationResult: Bool = false,
        postRequestAuthorizationStatus: UNAuthorizationStatus? = nil,
        shouldFailAdd: Bool = false,
        shouldSuspendNextAdd: Bool = false,
        pendingRequests: [CleanupReminderNotificationRequest] = []
    ) {
        self.authorizationStatus = authorizationStatus
        self.requestAuthorizationResult = requestAuthorizationResult
        self.postRequestAuthorizationStatus = postRequestAuthorizationStatus ?? authorizationStatus
        self.shouldFailAdd = shouldFailAdd
        self.shouldSuspendNextAdd = shouldSuspendNextAdd
        self.pendingRequests = Dictionary(
            uniqueKeysWithValues: pendingRequests.map { ($0.identifier, $0) }
        )
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatus
    }

    func requestAuthorization(options _: UNAuthorizationOptions) async -> Bool {
        didCallRequestAuthorization = true
        authorizationStatus = postRequestAuthorizationStatus
        return requestAuthorizationResult
    }

    func add(_ request: CleanupReminderNotificationRequest) async throws {
        addAttemptCount += 1
        if shouldSuspendNextAdd {
            shouldSuspendNextAdd = false
            await withCheckedContinuation { continuation in
                suspendedAddContinuation = continuation
                suspendedAddWaiters.forEach { $0.resume() }
                suspendedAddWaiters.removeAll()
            }
        }
        if shouldFailAdd {
            throw TestNotificationCenterError.addFailed
        }
        addedRequests.append(request)
        pendingRequests[request.identifier] = request
    }

    func waitUntilAddIsSuspended() async {
        guard suspendedAddContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            suspendedAddWaiters.append(continuation)
        }
    }

    func resumeSuspendedAdd() {
        suspendedAddContinuation?.resume()
        suspendedAddContinuation = nil
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        removedIdentifiers.append(contentsOf: identifiers)
        for identifier in identifiers {
            pendingRequests.removeValue(forKey: identifier)
        }
    }
}

private func makeReminderRequest(
    schedule: CleanupReminderSchedule
) -> CleanupReminderNotificationRequest {
    CleanupReminderNotificationRequest(
        identifier: "cleanup.weekly.reminder",
        title: "Title",
        body: "Body",
        schedule: schedule,
        repeats: true
    )
}
