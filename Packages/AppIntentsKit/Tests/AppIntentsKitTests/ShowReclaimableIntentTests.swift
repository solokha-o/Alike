import XCTest
@testable import AppIntentsKit

final class ShowReclaimableIntentTests: XCTestCase {
    private let environment = TestEnvironment.shared

    override func setUp() {
        super.setUp()
        environment.reset()
    }

    func testReturnsTheBytesAndSpeaksAFormattedSize() async throws {
        let bytes: Int64 = 1_234_567_890
        environment.reset(summary: ReclaimableSummary(totalBytes: bytes, clusterCount: 12, lastScanDate: Date()))

        let result = try await ShowReclaimableIntent.forTest().perform()

        XCTAssertEqual(result.intentValue, Int(bytes))
        let expected = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        XCTAssertTrue(
            result.dialogText.contains(expected),
            "dialog should carry the formatted size \(expected): \(result.dialogText)"
        )
    }

    func testWithoutAScanItAsksToScanFirstAndReturnsZero() async throws {
        let result = try await ShowReclaimableIntent.forTest().perform()

        XCTAssertEqual(result.intentValue, 0)
        XCTAssertTrue(result.dialogText.contains(AppIntentsL10n.ShowReclaimable.scanFirst), result.dialogText)
    }

    func testATidyLibrarySaysSoInsteadOfZeroBytes() async throws {
        environment.reset(summary: ReclaimableSummary(totalBytes: 0, clusterCount: 0, lastScanDate: Date()))

        let result = try await ShowReclaimableIntent.forTest().perform()

        XCTAssertEqual(result.intentValue, 0)
        XCTAssertTrue(result.dialogText.contains(AppIntentsL10n.ShowReclaimable.nothingToFree), result.dialogText)
    }

    func testDoesNotOpenTheApp() async throws {
        XCTAssertFalse(ShowReclaimableIntent.openAppWhenRun)
        _ = try await ShowReclaimableIntent.forTest().perform()
        XCTAssertEqual(environment.opened, [])
    }
}
