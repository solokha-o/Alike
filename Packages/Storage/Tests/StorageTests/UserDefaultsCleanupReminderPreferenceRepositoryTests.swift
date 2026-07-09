import XCTest
@testable import Storage

final class UserDefaultsCleanupReminderPreferenceRepositoryTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var repository: UserDefaultsCleanupReminderPreferenceRepository!
    private let suiteName = "UserDefaultsCleanupReminderPreferenceRepositoryTests"
    private let reminderEnabledKey = "cleanup.reminder.test.isEnabled"

    override func setUpWithError() throws {
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        repository = UserDefaultsCleanupReminderPreferenceRepository(
            userDefaults: userDefaults,
            reminderEnabledKey: reminderEnabledKey
        )
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        repository = nil
        userDefaults = nil
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
}
