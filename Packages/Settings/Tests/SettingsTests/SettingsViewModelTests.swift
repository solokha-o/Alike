import XCTest
import Core
@testable import Settings

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testHandleRateTappedTriggersReview() {
        let viewModel = SettingsViewModel(gridConfig: .iPhone, appVersion: "1.2.3")
        var didCall = false

        XCTAssertEqual(viewModel.reviewTrigger, 0)
        viewModel.handleRateTapped(requestReview: {
            didCall = true
        })

        XCTAssertTrue(didCall)
        XCTAssertEqual(viewModel.reviewTrigger, 1)
    }

    func testRescanRequiredAfterSensitivityChangeIsTrue() {
        let viewModel = SettingsViewModel(gridConfig: .iPhone, appVersion: "1.2.3")
        XCTAssertTrue(viewModel.rescanRequiredAfterSensitivityChange())
    }

    func testInitUsesProvidedValues() {
        let viewModel = SettingsViewModel(gridConfig: .iPad, appVersion: "9.9.9")

        XCTAssertEqual(viewModel.gridConfig.defaultColumns, GridConfiguration.iPad.defaultColumns)
        XCTAssertEqual(viewModel.gridConfig.spacing, GridConfiguration.iPad.spacing)
        XCTAssertEqual(viewModel.appVersion, "9.9.9")
    }

    func testLoadCleanupInsightsKeepsEmptyStateWithoutHistory() async {
        let repository = MockCleanupHistoryRepository(entries: [])
        let viewModel = SettingsViewModel(
            gridConfig: .iPhone,
            appVersion: "1.2.3",
            cleanupHistoryRepository: repository
        )

        await viewModel.loadCleanupInsights()

        XCTAssertEqual(viewModel.cleanupInsights, .empty)
        XCTAssertFalse(viewModel.cleanupInsights.hasHistory)
    }

    func testLoadCleanupInsightsAggregatesHistory() async {
        let oldRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 1,
            estimatedSavingsBytes: 256,
            completedAt: Date(timeIntervalSince1970: 1_000)
        )
        let latestRecord = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 4,
            estimatedSavingsBytes: 4_096,
            completedAt: Date(timeIntervalSince1970: 2_000)
        )
        let repository = MockCleanupHistoryRepository(entries: [oldRecord, latestRecord])
        let viewModel = SettingsViewModel(
            gridConfig: .iPhone,
            appVersion: "1.2.3",
            cleanupHistoryRepository: repository
        )

        await viewModel.loadCleanupInsights()

        XCTAssertEqual(viewModel.cleanupInsights.totalDeletedItems, 5)
        XCTAssertEqual(viewModel.cleanupInsights.totalSavedBytes, 4_352)
        XCTAssertEqual(viewModel.cleanupInsights.cleanupSessionCount, 2)
        XCTAssertEqual(viewModel.cleanupInsights.latestCleanup, latestRecord)
    }

    func testDefaultAppVersionIsNonEmpty() {
        let version = SettingsViewModel.defaultAppVersion()
        XCTAssertFalse(version.isEmpty)
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
            gridConfig: .iPhone,
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
            gridConfig: .iPhone,
            appVersion: "1.2.3",
            cleanupReminderManager: reminderManager
        )

        await viewModel.setCleanupReminderEnabled(true, isPremiumUnlocked: true)

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
            gridConfig: .iPhone,
            appVersion: "1.2.3",
            cleanupReminderManager: reminderManager
        )

        await viewModel.setCleanupReminderEnabled(true, isPremiumUnlocked: true)

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
            gridConfig: .iPhone,
            appVersion: "1.2.3",
            cleanupReminderManager: reminderManager
        )

        await viewModel.setCleanupReminderEnabled(false, isPremiumUnlocked: true)

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
            gridConfig: .iPhone,
            appVersion: "1.2.3",
            cleanupReminderManager: reminderManager
        )

        await viewModel.setCleanupReminderSchedule(customSchedule, isPremiumUnlocked: true)

        XCTAssertEqual(viewModel.cleanupReminderState.schedule, customSchedule)
        XCTAssertFalse(viewModel.isUpdatingCleanupReminder)
    }
}
