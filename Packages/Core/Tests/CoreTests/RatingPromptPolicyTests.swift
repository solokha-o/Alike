import XCTest
@testable import Core

final class RatingPromptPolicyTests: XCTestCase {
    private let policy = RatingPromptPolicy()
    private let appVersion = "1.4.0"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeContext(
        deletedCount: Int = 10,
        isBusy: Bool = false,
        appVersion: String? = nil
    ) -> RatingPromptPolicy.Context {
        RatingPromptPolicy.Context(
            deletedCount: deletedCount,
            now: now,
            appVersion: appVersion ?? self.appVersion,
            isBusy: isBusy
        )
    }

    private func makeHistory(
        installedDaysAgo: Double = 30,
        lastPromptedDaysAgo: Double? = nil,
        lastPromptedAppVersion: String? = nil,
        promptCount: Int = 0
    ) -> RatingPromptHistory {
        RatingPromptHistory(
            firstLaunchDate: now.addingTimeInterval(-installedDaysAgo * 86_400),
            lastPromptedDate: lastPromptedDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) },
            lastPromptedAppVersion: lastPromptedAppVersion,
            promptCount: promptCount
        )
    }

    func testEligibleAfterMeaningfulCleanupOnEstablishedInstall() {
        XCTAssertTrue(policy.shouldRequestReview(history: makeHistory(), context: makeContext()))
    }

    func testTooFewDeletedItemsIsNotEligible() {
        XCTAssertFalse(
            policy.shouldRequestReview(
                history: makeHistory(),
                context: makeContext(deletedCount: 2)
            )
        )
    }

    func testBusySurfaceIsNotEligible() {
        XCTAssertFalse(
            policy.shouldRequestReview(
                history: makeHistory(),
                context: makeContext(isBusy: true)
            )
        )
    }

    func testFreshInstallIsNotEligible() {
        XCTAssertFalse(
            policy.shouldRequestReview(
                history: makeHistory(installedDaysAgo: 1),
                context: makeContext()
            )
        )
    }

    func testMissingInstallDateIsNotEligible() {
        XCTAssertFalse(
            policy.shouldRequestReview(
                history: RatingPromptHistory(),
                context: makeContext()
            )
        )
    }

    func testInsideCooldownIsNotEligible() {
        XCTAssertFalse(
            policy.shouldRequestReview(
                history: makeHistory(
                    installedDaysAgo: 400,
                    lastPromptedDaysAgo: 30,
                    lastPromptedAppVersion: "1.2.0",
                    promptCount: 1
                ),
                context: makeContext()
            )
        )
    }

    func testOutsideCooldownOnNewVersionIsEligible() {
        XCTAssertTrue(
            policy.shouldRequestReview(
                history: makeHistory(
                    installedDaysAgo: 400,
                    lastPromptedDaysAgo: 200,
                    lastPromptedAppVersion: "1.2.0",
                    promptCount: 1
                ),
                context: makeContext()
            )
        )
    }

    func testSameAppVersionIsNotEligible() {
        XCTAssertFalse(
            policy.shouldRequestReview(
                history: makeHistory(
                    installedDaysAgo: 400,
                    lastPromptedDaysAgo: 200,
                    lastPromptedAppVersion: appVersion,
                    promptCount: 1
                ),
                context: makeContext()
            )
        )
    }

    func testLifetimeBudgetExhaustedIsNotEligible() {
        XCTAssertFalse(
            policy.shouldRequestReview(
                history: makeHistory(
                    installedDaysAgo: 2_000,
                    lastPromptedDaysAgo: 500,
                    lastPromptedAppVersion: "1.2.0",
                    promptCount: 3
                ),
                context: makeContext()
            )
        )
    }
}
