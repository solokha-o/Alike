import XCTest
@testable import Diagnostics

final class CrashReportPromptPolicyTests: XCTestCase {
    private let policy = CrashReportPromptPolicy()

    private func report(_ second: TimeInterval, _ state: CrashReport.PromptState) -> CrashReport {
        CrashReport(receivedAt: Date(timeIntervalSince1970: second), promptState: state)
    }

    func testNothingStoredMeansNoPrompt() {
        XCTAssertNil(policy.prompt(for: [], isBusy: false))
    }

    func testPendingReportsShareOnePromptNewestFirst() {
        let older = report(10, .pending)
        let newer = report(20, .pending)

        let prompt = policy.prompt(for: [older, newer], isBusy: false)

        XCTAssertEqual(prompt?.reports, [newer, older])
        XCTAssertEqual(prompt?.id, newer.id)
    }

    func testEveryNonPendingStateIsNeverAskedAbout() {
        let reports = [report(10, .prompted), report(20, .declined), report(30, .sent)]

        XCTAssertNil(policy.prompt(for: reports, isBusy: false))
    }

    func testBusyScreenSuppressesThePrompt() {
        XCTAssertNil(policy.prompt(for: [report(10, .pending)], isBusy: true))
    }
}
