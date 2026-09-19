import XCTest
@testable import Diagnostics

final class CrashReportMailDraftTests: XCTestCase {
    private let fallback = CrashReportMailDraft.Fallback(
        appVersion: "9.9.9",
        appBuild: "99",
        osVersion: "iOS 27.0",
        deviceModel: "iPhone99,9"
    )

    private func draft(_ reports: [CrashReport], urls: [URL] = []) -> CrashReportMailDraft {
        CrashReportMailDraft(
            prompt: CrashReportPrompt(reports: reports),
            attachmentURLs: urls,
            body: "body",
            fallback: fallback
        )
    }

    func testSubjectDescribesTheBuildThatCrashedNotTheOneRunning() {
        let report = CrashReport(
            receivedAt: Date(timeIntervalSince1970: 10),
            appVersion: "1.4.0",
            appBuild: "10",
            osVersion: "iPhone OS 18.6 (22G86)",
            deviceModel: "iPhone14,3"
        )

        XCTAssertEqual(draft([report]).subject, "Alike crash 1.4.0 (10) — iOS 18.6 — iPhone14,3")
    }

    func testSubjectFallsBackWhereThePayloadSaidNothing() {
        let report = CrashReport(receivedAt: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(draft([report]).subject, "Alike crash 9.9.9 (99) — iOS 27.0 — iPhone99,9")
    }

    func testSubjectComesFromTheNewestReport() {
        let newest = CrashReport(receivedAt: Date(timeIntervalSince1970: 20), appVersion: "1.5.0", appBuild: "12")
        let older = CrashReport(receivedAt: Date(timeIntervalSince1970: 10), appVersion: "1.4.0", appBuild: "10")

        XCTAssertTrue(draft([newest, older]).subject.hasPrefix("Alike crash 1.5.0 (12)"))
    }

    func testOSVersionDisplay() {
        XCTAssertEqual(CrashReportMailDraft.displayOSVersion("iPhone OS 18.6 (22G86)"), "iOS 18.6")
        XCTAssertEqual(CrashReportMailDraft.displayOSVersion("iPadOS 18.6.1 (22G90)"), "iOS 18.6.1")
        XCTAssertEqual(CrashReportMailDraft.displayOSVersion("visionOS 3.0"), "visionOS 3.0")
    }

    func testRecipientIsTheSupportAddressAndEveryPayloadIsAttached() {
        let urls = [URL(fileURLWithPath: "/tmp/a.json"), URL(fileURLWithPath: "/tmp/b.json")]
        let reports = [
            CrashReport(receivedAt: Date(timeIntervalSince1970: 20)),
            CrashReport(receivedAt: Date(timeIntervalSince1970: 10))
        ]

        let draft = draft(reports, urls: urls)

        XCTAssertEqual(draft.recipient, CrashReportSupport.email)
        XCTAssertEqual(draft.attachments.map(\.fileURL), urls)
        XCTAssertEqual(draft.attachments.map(\.fileName), ["alike-crash-1.json", "alike-crash-2.json"])
    }
}
