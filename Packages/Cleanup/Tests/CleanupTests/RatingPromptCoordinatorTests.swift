import XCTest
import Core
@testable import Cleanup

@MainActor
final class RatingPromptCoordinatorTests: XCTestCase {
    private let appVersion = "1.4.0"
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    private final class TestClock: @unchecked Sendable {
        var now: Date

        init(now: Date) {
            self.now = now
        }
    }

    private func makeCoordinator(
        repository: MockRatingPromptHistoryRepository,
        clock: TestClock
    ) -> RatingPromptCoordinator {
        RatingPromptCoordinator(
            repository: repository,
            now: { clock.now },
            appVersion: appVersion
        )
    }

    private func makeRecord(deletedCount: Int) -> CleanupCompletionRecord {
        CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: deletedCount,
            estimatedSavingsBytes: 1_024
        )
    }

    private func establishedHistory() -> RatingPromptHistory {
        RatingPromptHistory(firstLaunchDate: referenceDate.addingTimeInterval(-30 * 86_400))
    }

    func testFirstEligibleCleanupRequestsReviewAndRecordsHistory() async {
        let repository = MockRatingPromptHistoryRepository(history: establishedHistory())
        let clock = TestClock(now: referenceDate)
        let coordinator = makeCoordinator(repository: repository, clock: clock)

        let shouldRequest = await coordinator.requestReviewIfEligible(
            after: makeRecord(deletedCount: 12),
            isBusy: false
        )

        XCTAssertTrue(shouldRequest)
        let history = await repository.currentHistory()
        XCTAssertEqual(history.promptCount, 1)
        XCTAssertEqual(history.lastPromptedDate, referenceDate)
        XCTAssertEqual(history.lastPromptedAppVersion, appVersion)
    }

    func testSecondCleanupInSameSessionDoesNotRequestReview() async {
        let repository = MockRatingPromptHistoryRepository(history: establishedHistory())
        let clock = TestClock(now: referenceDate)
        let coordinator = makeCoordinator(repository: repository, clock: clock)

        _ = await coordinator.requestReviewIfEligible(
            after: makeRecord(deletedCount: 12),
            isBusy: false
        )
        let shouldRequestAgain = await coordinator.requestReviewIfEligible(
            after: makeRecord(deletedCount: 12),
            isBusy: false
        )

        XCTAssertFalse(shouldRequestAgain)
        let history = await repository.currentHistory()
        XCTAssertEqual(history.promptCount, 1)
    }

    func testBusySurfaceDoesNotSpendAPrompt() async {
        let repository = MockRatingPromptHistoryRepository(history: establishedHistory())
        let clock = TestClock(now: referenceDate)
        let coordinator = makeCoordinator(repository: repository, clock: clock)

        let shouldRequest = await coordinator.requestReviewIfEligible(
            after: makeRecord(deletedCount: 12),
            isBusy: true
        )

        XCTAssertFalse(shouldRequest)
        let history = await repository.currentHistory()
        XCTAssertEqual(history.promptCount, 0)
    }

    func testManualRatingBlocksTheAutomaticPrompt() async {
        let repository = MockRatingPromptHistoryRepository(history: establishedHistory())
        let clock = TestClock(now: referenceDate)
        let coordinator = makeCoordinator(repository: repository, clock: clock)

        await coordinator.recordManualRating()
        clock.now = referenceDate.addingTimeInterval(86_400)

        let shouldRequest = await coordinator.requestReviewIfEligible(
            after: makeRecord(deletedCount: 12),
            isBusy: false
        )

        XCTAssertFalse(shouldRequest)
    }

    func testEligibleAgainAfterCooldownOnANewVersion() async {
        let repository = MockRatingPromptHistoryRepository(
            history: RatingPromptHistory(
                firstLaunchDate: referenceDate.addingTimeInterval(-400 * 86_400),
                lastPromptedDate: referenceDate.addingTimeInterval(-200 * 86_400),
                lastPromptedAppVersion: "1.2.0",
                promptCount: 1
            )
        )
        let clock = TestClock(now: referenceDate)
        let coordinator = makeCoordinator(repository: repository, clock: clock)

        let shouldRequest = await coordinator.requestReviewIfEligible(
            after: makeRecord(deletedCount: 5),
            isBusy: false
        )

        XCTAssertTrue(shouldRequest)
    }
}
