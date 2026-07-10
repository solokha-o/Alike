import XCTest
@testable import Storage

final class UserDefaultsCleanupReminderPreferenceRepositoryTests: XCTestCase {
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

    func testLoadReminderEnabledDefaultsToFalse() async {
        let isEnabled = await repository.loadReminderEnabled()
        XCTAssertFalse(isEnabled)
    }

    func testSaveReminderEnabledPersistsTrue() async {
        await repository.saveReminderEnabled(true)

        let isEnabled = await repository.loadReminderEnabled()
        XCTAssertTrue(isEnabled)
    }

    func testSaveReminderEnabledPersistsFalseOverwrite() async {
        await repository.saveReminderEnabled(true)
        await repository.saveReminderEnabled(false)

        let isEnabled = await repository.loadReminderEnabled()
        XCTAssertFalse(isEnabled)
    }

    func testLoadReminderScheduleDefaultsToWeeklySundayAtSixPm() async {
        let schedule = await repository.loadReminderSchedule()

        XCTAssertEqual(schedule, .defaultWeekly)
    }

    func testSaveReminderSchedulePersistsCustomValues() async {
        let schedule = CleanupReminderSchedule(weekday: 4, hour: 8, minute: 45)

        await repository.saveReminderSchedule(schedule)

        let persistedSchedule = await repository.loadReminderSchedule()
        XCTAssertEqual(persistedSchedule, schedule)
    }

    private func clearTestValues() {
        let userDefaults = UserDefaults.standard
        userDefaults.removeObject(forKey: reminderEnabledKey)
        userDefaults.removeObject(forKey: reminderWeekdayKey)
        userDefaults.removeObject(forKey: reminderHourKey)
        userDefaults.removeObject(forKey: reminderMinuteKey)
    }
}
