import XCTest
import Core
@testable import Settings

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testHandleRateTappedTriggersReview() {
        let viewModel = SettingsViewModel(appVersion: "1.2.3")
        var didCall = false

        XCTAssertEqual(viewModel.reviewTrigger, 0)
        viewModel.handleRateTapped(requestReview: {
            didCall = true
        })

        XCTAssertTrue(didCall)
        XCTAssertEqual(viewModel.reviewTrigger, 1)
    }

    func testRescanRequiredAfterSensitivityChangeIsTrue() {
        let viewModel = SettingsViewModel(appVersion: "1.2.3")
        XCTAssertTrue(viewModel.rescanRequiredAfterSensitivityChange())
    }

    func testInitUsesProvidedValues() {
        let viewModel = SettingsViewModel(appVersion: "9.9.9")

        XCTAssertEqual(viewModel.appVersion, "9.9.9")
    }

    func testFullAppVersionIsNonEmptyAndIncludesBuild() {
        let version = SettingsViewModel.fullAppVersion()
        XCTAssertFalse(version.isEmpty)
        XCTAssertTrue(version.contains("("))
        XCTAssertTrue(version.hasSuffix(")"))
    }

    func testLoadCleanupReminderStateReflectsDeniedStatus() async {
        let reminderManager = MockCleanupReminderManager(
            state: CleanupReminderState(
                isEnabled: false,
                authorizationStatus: .denied,
                schedule: .defaultWeekly,
                isScheduleCustomizationLocked: false
            )
        )
        let viewModel = SettingsViewModel(
            appVersion: "1.2.3",
            cleanupReminderManager: reminderManager
        )

        await viewModel.loadCleanupReminderState(isPremiumUnlocked: true)

        XCTAssertEqual(
            viewModel.cleanupReminderState,
            CleanupReminderState(
                isEnabled: false,
                authorizationStatus: .denied,
                schedule: .defaultWeekly,
                isScheduleCustomizationLocked: false
            )
        )
    }

    func testSetCleanupReminderEnabledTurnsReminderOn() async {
        let reminderManager = MockCleanupReminderManager()
        await reminderManager.setState(
            CleanupReminderState(
                isEnabled: false,
                authorizationStatus: .authorized,
                schedule: .defaultWeekly,
                isScheduleCustomizationLocked: false
            )
        )
        await reminderManager.setSetEnabledResultState(
            CleanupReminderState(
            isEnabled: true,
            authorizationStatus: .authorized,
            schedule: .defaultWeekly,
            isScheduleCustomizationLocked: false
            )
        )
        let viewModel = SettingsViewModel(
            appVersion: "1.2.3",
            cleanupReminderManager: reminderManager
        )

        viewModel.setCleanupReminderEnabled(true, isPremiumUnlocked: true)
        await viewModel.waitForCleanupReminderMutation()

        XCTAssertTrue(viewModel.cleanupReminderState.isEnabled)
        XCTAssertFalse(viewModel.isUpdatingCleanupReminder)
    }

    func testSetCleanupReminderEnabledKeepsReminderOffWhenDenied() async {
        let reminderManager = MockCleanupReminderManager(
            state: CleanupReminderState(
                isEnabled: false,
                authorizationStatus: .denied,
                schedule: .defaultWeekly,
                isScheduleCustomizationLocked: false
            )
        )
        await reminderManager.setSetEnabledResultState(
            CleanupReminderState(
            isEnabled: false,
            authorizationStatus: .denied,
            schedule: .defaultWeekly,
            isScheduleCustomizationLocked: false
            )
        )
        let viewModel = SettingsViewModel(
            appVersion: "1.2.3",
            cleanupReminderManager: reminderManager
        )

        viewModel.setCleanupReminderEnabled(true, isPremiumUnlocked: true)
        await viewModel.waitForCleanupReminderMutation()

        XCTAssertFalse(viewModel.cleanupReminderState.isEnabled)
        XCTAssertEqual(viewModel.cleanupReminderState.authorizationStatus, .denied)
    }

    func testSetCleanupReminderEnabledTurnsReminderOff() async {
        let reminderManager = MockCleanupReminderManager(
            state: CleanupReminderState(
                isEnabled: true,
                authorizationStatus: .authorized,
                schedule: .defaultWeekly,
                isScheduleCustomizationLocked: false
            )
        )
        await reminderManager.setSetEnabledResultState(
            CleanupReminderState(
            isEnabled: false,
            authorizationStatus: .authorized,
            schedule: .defaultWeekly,
            isScheduleCustomizationLocked: false
            )
        )
        let viewModel = SettingsViewModel(
            appVersion: "1.2.3",
            cleanupReminderManager: reminderManager
        )

        viewModel.setCleanupReminderEnabled(false, isPremiumUnlocked: true)
        await viewModel.waitForCleanupReminderMutation()

        XCTAssertFalse(viewModel.cleanupReminderState.isEnabled)
        XCTAssertEqual(viewModel.cleanupReminderState.authorizationStatus, .authorized)
    }

    func testSetCleanupReminderScheduleUpdatesState() async {
        let customSchedule = CleanupReminderSchedule(weekday: 4, hour: 7, minute: 20)
        let reminderManager = MockCleanupReminderManager(
            state: CleanupReminderState(
                isEnabled: true,
                authorizationStatus: .authorized,
                schedule: .defaultWeekly,
                isScheduleCustomizationLocked: false
            )
        )
        await reminderManager.setSetScheduleResultState(
            CleanupReminderState(
                isEnabled: true,
                authorizationStatus: .authorized,
                schedule: customSchedule,
                isScheduleCustomizationLocked: false
            )
        )
        let viewModel = SettingsViewModel(
            appVersion: "1.2.3",
            cleanupReminderManager: reminderManager
        )

        viewModel.setCleanupReminderSchedule(customSchedule, isPremiumUnlocked: true)
        await viewModel.waitForCleanupReminderMutation()

        XCTAssertEqual(viewModel.cleanupReminderState.schedule, customSchedule)
        XCTAssertFalse(viewModel.isUpdatingCleanupReminder)
    }

    func testSetCleanupReminderEnabledFailureReloadsStateAndPresentsError() async {
        let authoritativeState = CleanupReminderState(
            isEnabled: false,
            authorizationStatus: .authorized,
            schedule: .defaultWeekly,
            isScheduleCustomizationLocked: false
        )
        let reminderManager = MockCleanupReminderManager(state: authoritativeState)
        await reminderManager.setShouldFailSetEnabled(true)
        let viewModel = SettingsViewModel(
            appVersion: "1.2.3",
            cleanupReminderManager: reminderManager
        )

        viewModel.setCleanupReminderEnabled(true, isPremiumUnlocked: true)
        await viewModel.waitForCleanupReminderMutation()

        let didCallLoadState = await reminderManager.didCallLoadState
        XCTAssertEqual(viewModel.cleanupReminderState, authoritativeState)
        XCTAssertNotNil(viewModel.cleanupReminderErrorMessage)
        XCTAssertFalse(viewModel.isUpdatingCleanupReminder)
        XCTAssertTrue(didCallLoadState)

        viewModel.dismissCleanupReminderError()
        XCTAssertNil(viewModel.cleanupReminderErrorMessage)
    }

    func testSetCleanupReminderScheduleFailureReloadsAuthoritativeSchedule() async {
        let authoritativeState = CleanupReminderState(
            isEnabled: true,
            authorizationStatus: .authorized,
            schedule: .defaultWeekly,
            isScheduleCustomizationLocked: false
        )
        let reminderManager = MockCleanupReminderManager(state: authoritativeState)
        await reminderManager.setShouldFailSetSchedule(true)
        let viewModel = SettingsViewModel(
            appVersion: "1.2.3",
            cleanupReminderManager: reminderManager
        )

        viewModel.setCleanupReminderSchedule(
            CleanupReminderSchedule(weekday: 4, hour: 8, minute: 30),
            isPremiumUnlocked: true
        )
        await viewModel.waitForCleanupReminderMutation()

        XCTAssertEqual(viewModel.cleanupReminderState, authoritativeState)
        XCTAssertNotNil(viewModel.cleanupReminderErrorMessage)
        XCTAssertFalse(viewModel.isUpdatingCleanupReminder)
    }

    func testLatestScheduleMutationWinsWhenEarlierCompletionArrivesLast() async {
        let firstSchedule = CleanupReminderSchedule(weekday: 2, hour: 8, minute: 15)
        let latestSchedule = CleanupReminderSchedule(weekday: 5, hour: 18, minute: 45)
        let reminderManager = SuspendedFirstScheduleReminderManager()
        let viewModel = SettingsViewModel(
            appVersion: "1.2.3",
            cleanupReminderManager: reminderManager
        )

        viewModel.setCleanupReminderSchedule(firstSchedule, isPremiumUnlocked: true)
        await reminderManager.waitUntilFirstScheduleMutationStarts()

        viewModel.setCleanupReminderSchedule(latestSchedule, isPremiumUnlocked: true)
        await viewModel.waitForCleanupReminderMutation()

        XCTAssertEqual(viewModel.cleanupReminderState.schedule, latestSchedule)
        XCTAssertFalse(viewModel.isUpdatingCleanupReminder)

        await reminderManager.resumeFirstScheduleMutation()
        await Task.yield()

        XCTAssertEqual(viewModel.cleanupReminderState.schedule, latestSchedule)
        XCTAssertFalse(viewModel.isUpdatingCleanupReminder)
    }
}

private actor SuspendedFirstScheduleReminderManager: CleanupReminderManaging {
    private var firstScheduleContinuation: CheckedContinuation<Void, Never>?
    private var firstScheduleStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var scheduleCallCount = 0
    private var state = CleanupReminderState(
        isEnabled: true,
        authorizationStatus: .authorized,
        schedule: .defaultWeekly,
        isScheduleCustomizationLocked: false
    )

    func loadState(isPremiumUnlocked: Bool) async -> CleanupReminderState {
        state
    }

    func setEnabled(
        _ isEnabled: Bool,
        isPremiumUnlocked: Bool
    ) async throws -> CleanupReminderState {
        state
    }

    func setSchedule(
        _ schedule: CleanupReminderSchedule,
        isPremiumUnlocked: Bool
    ) async throws -> CleanupReminderState {
        scheduleCallCount += 1
        if scheduleCallCount == 1 {
            await withCheckedContinuation { continuation in
                firstScheduleContinuation = continuation
                firstScheduleStartWaiters.forEach { $0.resume() }
                firstScheduleStartWaiters.removeAll()
            }
        }

        let updatedState = CleanupReminderState(
            isEnabled: true,
            authorizationStatus: .authorized,
            schedule: schedule,
            isScheduleCustomizationLocked: false
        )
        state = updatedState
        return updatedState
    }

    func resync(isPremiumUnlocked: Bool) async throws {}

    func waitUntilFirstScheduleMutationStarts() async {
        guard firstScheduleContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            firstScheduleStartWaiters.append(continuation)
        }
    }

    func resumeFirstScheduleMutation() {
        firstScheduleContinuation?.resume()
        firstScheduleContinuation = nil
    }
}
