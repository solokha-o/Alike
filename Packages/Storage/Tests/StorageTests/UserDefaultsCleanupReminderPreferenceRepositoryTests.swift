import Foundation
import Testing
@testable import Storage

/// A `final class` suite: each test gets its own `UserDefaults` suite, and `deinit`
/// removes it. The repository is an actor and `UserDefaults` is not `Sendable`, so
/// each repository gets its own `UserDefaults` instance of that suite.
@Suite final class UserDefaultsCleanupReminderPreferenceRepositoryTests {
    private let suiteName = UUID().uuidString
    private let defaults: UserDefaults
    private let repository: UserDefaultsCleanupReminderPreferenceRepository
    private let reminderEnabledKey = "cleanup.reminder.test.isEnabled"
    private let reminderWeekdayKey = "cleanup.reminder.test.weekday"
    private let reminderHourKey = "cleanup.reminder.test.hour"
    private let reminderMinuteKey = "cleanup.reminder.test.minute"

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        repository = UserDefaultsCleanupReminderPreferenceRepository(
            userDefaults: try #require(UserDefaults(suiteName: suiteName)),
            reminderEnabledKey: reminderEnabledKey,
            reminderWeekdayKey: reminderWeekdayKey,
            reminderHourKey: reminderHourKey,
            reminderMinuteKey: reminderMinuteKey
        )
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
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
}
