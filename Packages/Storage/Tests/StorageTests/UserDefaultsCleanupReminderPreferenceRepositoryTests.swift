import Foundation
import Testing
@testable import Storage

@Suite struct UserDefaultsCleanupReminderPreferenceRepositoryTests {
    private var repository: UserDefaultsCleanupReminderPreferenceRepository!
    private let reminderEnabledKey = "cleanup.reminder.test.isEnabled"
    private let reminderWeekdayKey = "cleanup.reminder.test.weekday"
    private let reminderHourKey = "cleanup.reminder.test.hour"
    private let reminderMinuteKey = "cleanup.reminder.test.minute"

    override func setUpWithError() throws {
        clearTestValues()
        repository = UserDefaultsCleanupReminderPreferenceRepository(
            reminderEnabledKey: reminderEnabledKey,
            reminderWeekdayKey: reminderWeekdayKey,
            reminderHourKey: reminderHourKey,
            reminderMinuteKey: reminderMinuteKey
        )
    }

    override func tearDownWithError() throws {
        repository = nil
        clearTestValues()
    }

    @Test func testLoadReminderEnabledDefaultsToFalse() async {
        let isEnabled = await repository.loadReminderEnabled()
        #expect(!isEnabled)
    }

    @Test func testSaveReminderEnabledPersistsTrue() async {
        await repository.saveReminderEnabled(true)

        let isEnabled = await repository.loadReminderEnabled()
        #expect(isEnabled)
    }

    @Test func testSaveReminderEnabledPersistsFalseOverwrite() async {
        await repository.saveReminderEnabled(true)
        await repository.saveReminderEnabled(false)

        let isEnabled = await repository.loadReminderEnabled()
        #expect(!isEnabled)
    }

    @Test func testLoadReminderScheduleDefaultsToWeeklySundayAtSixPm() async {
        let schedule = await repository.loadReminderSchedule()

        #expect(schedule == .defaultWeekly)
    }

    @Test func testSaveReminderSchedulePersistsCustomValues() async {
        let schedule = CleanupReminderSchedule(weekday: 4, hour: 8, minute: 45)

        await repository.saveReminderSchedule(schedule)

        let persistedSchedule = await repository.loadReminderSchedule()
        #expect(persistedSchedule == schedule)
    }

    private func clearTestValues() {
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: reminderEnabledKey)
        userDefaults.removeObject(forKey: reminderWeekdayKey)
        userDefaults.removeObject(forKey: reminderHourKey)
        userDefaults.removeObject(forKey: reminderMinuteKey)
    }
}
