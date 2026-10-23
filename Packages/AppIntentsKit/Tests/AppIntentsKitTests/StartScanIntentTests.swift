import XCTest
@testable import AppIntentsKit

@MainActor
final class StartScanIntentTests: XCTestCase {
    private let environment = TestEnvironment.shared

    override func setUp() {
        super.setUp()
        environment.reset()
    }

    func testPerformAsksTheAppToOpenTheScannerWithAScan() async throws {
        _ = try await StartScanIntent.forTest().perform()

        XCTAssertEqual(environment.opened, [.scan])
    }

    func testOpensTheAppSoTheScannerOwnsQuotaAndPermission() {
        // The intent never scans by itself: `ScannerView` runs the free-scan quota and
        // the Photos permission prompt, and both need the app in front.
        XCTAssertTrue(StartScanIntent.openAppWhenRun)
    }
}
