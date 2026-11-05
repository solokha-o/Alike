import Foundation
import Testing
@testable import Core

@Suite struct RatingPromptPolicyTests {
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

    @Test func testEligibleAfterMeaningfulCleanupOnEstablishedInstall() {
        #expect(policy.shouldRequestReview(history: makeHistory(), context: makeContext()))
    }

    @Test func testTooFewDeletedItemsIsNotEligible() {
        #expect(
            !(policy.shouldRequestReview(
                history: makeHistory(),
                context: makeContext(deletedCount: 2)
            ))
        )
    }

    @Test func testBusySurfaceIsNotEligible() {
        #expect(
            !(policy.shouldRequestReview(
                history: makeHistory(),
                context: makeContext(isBusy: true)
            ))
        )
    }

    @Test func testFreshInstallIsNotEligible() {
        #expect(
            !(policy.shouldRequestReview(
                history: makeHistory(installedDaysAgo: 23.0 / 24),
                context: makeContext()
            ))
        )
    }

    @Test func testInstallOneDayOldIsEligible() {
        #expect(
            policy.shouldRequestReview(
                history: makeHistory(installedDaysAgo: 1),
                context: makeContext()
            )
        )
    }

    @Test func testMissingInstallDateIsNotEligible() {
        #expect(
            !(policy.shouldRequestReview(
                history: RatingPromptHistory(),
                context: makeContext()
            ))
        )
    }

    @Test func testInsideCooldownIsNotEligible() {
        #expect(
            !(policy.shouldRequestReview(
                history: makeHistory(
                    installedDaysAgo: 400,
                    lastPromptedDaysAgo: 30,
                    lastPromptedAppVersion: "1.2.0",
                    promptCount: 1
                ),
                context: makeContext()
            ))
        )
    }

    @Test func testOutsideCooldownOnNewVersionIsEligible() {
        #expect(
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

    @Test func testSameAppVersionIsNotEligible() {
        #expect(
            !(policy.shouldRequestReview(
                history: makeHistory(
                    installedDaysAgo: 400,
                    lastPromptedDaysAgo: 200,
                    lastPromptedAppVersion: appVersion,
                    promptCount: 1
                ),
                context: makeContext()
            ))
        )
    }

    @Test func testLifetimeBudgetExhaustedIsNotEligible() {
        #expect(
            !(policy.shouldRequestReview(
                history: makeHistory(
                    installedDaysAgo: 2_000,
                    lastPromptedDaysAgo: 500,
                    lastPromptedAppVersion: "1.2.0",
                    promptCount: 3
                ),
                context: makeContext()
            ))
        )
    }
}
