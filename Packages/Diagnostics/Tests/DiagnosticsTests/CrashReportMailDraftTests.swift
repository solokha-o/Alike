import Foundation
import Testing
@testable import Diagnostics

@Suite struct CrashReportMailDraftTests {
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

    @Test func testSubjectDescribesTheBuildThatCrashedNotTheOneRunning() {
        let report = CrashReport(
            receivedAt: Date(timeIntervalSince1970: 10),
            appVersion: "1.4.0",
            appBuild: "10",
            osVersion: "iPhone OS 18.6 (22G86)",
            deviceModel: "iPhone14,3"
        )

        #expect(draft([report]).subject == "Alike crash 1.4.0 (10) — iOS 18.6 — iPhone14,3")
    }

    @Test func testSubjectFallsBackWhereThePayloadSaidNothing() {
        let report = CrashReport(receivedAt: Date(timeIntervalSince1970: 10))

        #expect(draft([report]).subject == "Alike crash 9.9.9 (99) — iOS 27.0 — iPhone99,9")
    }

    @Test func testSubjectComesFromTheNewestReport() {
        let newest = CrashReport(receivedAt: Date(timeIntervalSince1970: 20), appVersion: "1.5.0", appBuild: "12")
        let older = CrashReport(receivedAt: Date(timeIntervalSince1970: 10), appVersion: "1.4.0", appBuild: "10")

        #expect(draft([newest, older]).subject.hasPrefix("Alike crash 1.5.0 (12)"))
    }

    @Test func testOSVersionDisplay() {
        #expect(CrashReportMailDraft.displayOSVersion("iPhone OS 18.6 (22G86)") == "iOS 18.6")
        #expect(CrashReportMailDraft.displayOSVersion("iPadOS 18.6.1 (22G90)") == "iOS 18.6.1")
        #expect(CrashReportMailDraft.displayOSVersion("visionOS 3.0") == "visionOS 3.0")
    }

    @Test func testRecipientIsTheSupportAddressAndEveryPayloadIsAttached() {
        let urls = [URL(fileURLWithPath: "/tmp/a.json"), URL(fileURLWithPath: "/tmp/b.json")]
        let reports = [
            CrashReport(receivedAt: Date(timeIntervalSince1970: 20)),
            CrashReport(receivedAt: Date(timeIntervalSince1970: 10))
        ]

        let draft = draft(reports, urls: urls)

        #expect(draft.recipient == CrashReportSupport.email)
        #expect(draft.attachments.map(\.fileURL) == urls)
        #expect(draft.attachments.map(\.fileName) == ["alike-crash-1.json", "alike-crash-2.json"])
    }

    /// `ShareLink` has no recipient field, so the only place the address can travel is
    /// the message text — without it the fallback hands the user a report and no address.
    @Test func testShareBodyCarriesTheRecipientAndTheMailBody() {
        let draft = draft([CrashReport(receivedAt: Date(timeIntervalSince1970: 10))])

        #expect(draft.shareBody.contains(CrashReportSupport.email))
        #expect(draft.shareBody.hasSuffix(draft.body))
    }
}
