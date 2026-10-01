import XCTest
import Core
@testable import Storage

final class UserDefaultsRatingPromptHistoryRepositoryTests: XCTestCase {
    private var key: String!
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        key = "rating.promptHistory.test.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        key = nil
    }

    func testFirstLoadOnAFreshInstallSeedsFirstLaunchDate() async {
        let repository = makeRepository()

        let history = await repository.loadHistory(now: referenceDate)

        XCTAssertEqual(history.firstLaunchDate, referenceDate)
    }

    func testSubsequentLoadsDoNotOverwriteTheSeededFirstLaunchDate() async {
        let repository = makeRepository()
        _ = await repository.loadHistory(now: referenceDate)

        let laterHistory = await repository.loadHistory(
            now: referenceDate.addingTimeInterval(30 * 86_400)
        )

        XCTAssertEqual(laterHistory.firstLaunchDate, referenceDate)
    }

    /// Storage-path counterpart to the "established install" scenario in
    /// `RatingPromptPolicyTests`: an installation whose `firstLaunchDate` was already
    /// seeded (e.g. at app launch, well before any cleanup ran) must keep reporting that
    /// original date, not the moment of the first read that happens to matter to a caller.
    func testLoadOnAnEstablishedInstallReportsTheOriginalInstallDateNotTheCurrentRead() async {
        let installDate = referenceDate.addingTimeInterval(-30 * 86_400)
        let seedingRepository = makeRepository()
        _ = await seedingRepository.loadHistory(now: installDate)

        // A new repository instance simulates a fresh process reading persisted state,
        // the same way the app does across launches.
        let laterRepository = makeRepository()
        let history = await laterRepository.loadHistory(now: referenceDate)

        XCTAssertEqual(history.firstLaunchDate, installDate)
        XCTAssertNotEqual(
            history.firstLaunchDate,
            referenceDate,
            "An established install must not be re-stamped as brand new on a later read"
        )
    }

    /// A payload written by a shipped build, including a prompt recorded from the old
    /// Settings rate button, must still decode field for field: the policy change only moves
    /// a default and never rewrites stored history.
    func testShippedPayloadDecodesUnchanged() async throws {
        // Foundation's default JSONEncoder stores dates as seconds since 2001-01-01.
        let shipped = #"{"firstLaunchDate":800000000,"lastPromptedDate":801000000,"lastPromptedAppVersion":"1.6.1","promptCount":1}"#
        UserDefaults.standard.set(try XCTUnwrap(shipped.data(using: .utf8)), forKey: key)

        let history = await makeRepository().loadHistory(now: referenceDate)

        XCTAssertEqual(history.firstLaunchDate, Date(timeIntervalSinceReferenceDate: 800_000_000))
        XCTAssertEqual(history.lastPromptedDate, Date(timeIntervalSinceReferenceDate: 801_000_000))
        XCTAssertEqual(history.lastPromptedAppVersion, "1.6.1")
        XCTAssertEqual(history.promptCount, 1)
    }

    func testRecordPromptShownSeedsFirstLaunchDateWhenNoPriorReadHappened() async {
        let repository = makeRepository()

        await repository.recordPromptShown(at: referenceDate, appVersion: "1.4.0")

        let history = await repository.loadHistory(now: referenceDate.addingTimeInterval(86_400))
        XCTAssertEqual(history.firstLaunchDate, referenceDate)
    }

    private func makeRepository() -> UserDefaultsRatingPromptHistoryRepository {
        UserDefaultsRatingPromptHistoryRepository(defaults: .standard, historyKey: key)
    }
}
