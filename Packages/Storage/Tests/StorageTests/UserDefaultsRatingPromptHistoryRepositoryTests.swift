import Foundation
import Testing
import Core
@testable import Storage

/// A `final class` suite: each test gets its own `UserDefaults` suite, and `deinit`
/// removes it. The repository is an actor and `UserDefaults` is not `Sendable`, so
/// each repository gets its own `UserDefaults` instance of that suite.
@Suite final class UserDefaultsRatingPromptHistoryRepositoryTests {
    private let suiteName = UUID().uuidString
    private let defaults: UserDefaults
    private let key = "rating.promptHistory.test.\(UUID().uuidString)"
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func testFirstLoadOnAFreshInstallSeedsFirstLaunchDate() async {
        let repository = makeRepository()

        let history = await repository.loadHistory(now: referenceDate)

        #expect(history.firstLaunchDate == referenceDate)
    }

    @Test func testSubsequentLoadsDoNotOverwriteTheSeededFirstLaunchDate() async {
        let repository = makeRepository()
        _ = await repository.loadHistory(now: referenceDate)

        let laterHistory = await repository.loadHistory(
            now: referenceDate.addingTimeInterval(30 * 86_400)
        )

        #expect(laterHistory.firstLaunchDate == referenceDate)
    }

    /// Storage-path counterpart to the "established install" scenario in
    /// `RatingPromptPolicyTests`: an installation whose `firstLaunchDate` was already
    /// seeded (e.g. at app launch, well before any cleanup ran) must keep reporting that
    /// original date, not the moment of the first read that happens to matter to a caller.
    @Test func testLoadOnAnEstablishedInstallReportsTheOriginalInstallDateNotTheCurrentRead() async {
        let installDate = referenceDate.addingTimeInterval(-30 * 86_400)
        let seedingRepository = makeRepository()
        _ = await seedingRepository.loadHistory(now: installDate)

        // A new repository instance simulates a fresh process reading persisted state,
        // the same way the app does across launches.
        let laterRepository = makeRepository()
        let history = await laterRepository.loadHistory(now: referenceDate)

        #expect(history.firstLaunchDate == installDate)
        #expect(
            history.firstLaunchDate != referenceDate,
            "An established install must not be re-stamped as brand new on a later read"
        )
    }

    /// A payload written by a shipped build, including a prompt recorded from the old
    /// Settings rate button, must still decode field for field: the policy change only moves
    /// a default and never rewrites stored history.
    @Test func testShippedPayloadDecodesUnchanged() async throws {
        // Foundation's default JSONEncoder stores dates as seconds since 2001-01-01.
        let shipped = #"{"firstLaunchDate":800000000,"lastPromptedDate":801000000,"lastPromptedAppVersion":"1.6.1","promptCount":1}"#
        defaults.set(try #require(shipped.data(using: .utf8)), forKey: key)

        let history = await makeRepository().loadHistory(now: referenceDate)

        #expect(history.firstLaunchDate == Date(timeIntervalSinceReferenceDate: 800_000_000))
        #expect(history.lastPromptedDate == Date(timeIntervalSinceReferenceDate: 801_000_000))
        #expect(history.lastPromptedAppVersion == "1.6.1")
        #expect(history.promptCount == 1)
    }

    @Test func testRecordPromptShownSeedsFirstLaunchDateWhenNoPriorReadHappened() async {
        let repository = makeRepository()

        await repository.recordPromptShown(at: referenceDate, appVersion: "1.4.0")

        let history = await repository.loadHistory(now: referenceDate.addingTimeInterval(86_400))
        #expect(history.firstLaunchDate == referenceDate)
    }

    private func makeRepository() -> UserDefaultsRatingPromptHistoryRepository {
        UserDefaultsRatingPromptHistoryRepository(defaults: UserDefaults(suiteName: suiteName)!, historyKey: key)
    }
}
