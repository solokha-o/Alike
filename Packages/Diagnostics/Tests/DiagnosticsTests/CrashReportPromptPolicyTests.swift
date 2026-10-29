import Foundation
import Testing
@testable import Diagnostics

@Suite struct CrashReportPromptPolicyTests {
    private let policy = CrashReportPromptPolicy()

    private func report(_ second: TimeInterval, _ state: CrashReport.PromptState) -> CrashReport {
        CrashReport(receivedAt: Date(timeIntervalSince1970: second), promptState: state)
    }

    @Test func testNothingStoredMeansNoPrompt() {
        #expect(policy.prompt(for: [], isBusy: false) == nil)
    }

    @Test func testPendingReportsShareOnePromptNewestFirst() {
        let older = report(10, .pending)
        let newer = report(20, .pending)

        let prompt = policy.prompt(for: [older, newer], isBusy: false)

        #expect(prompt?.reports == [newer, older])
        #expect(prompt?.id == newer.id)
    }

    @Test func testEveryNonPendingStateIsNeverAskedAbout() {
        let reports = [report(10, .prompted), report(20, .declined), report(30, .sent)]

        #expect(policy.prompt(for: reports, isBusy: false) == nil)
    }

    @Test func testBusyScreenSuppressesThePrompt() {
        #expect(policy.prompt(for: [report(10, .pending)], isBusy: true) == nil)
    }
}
