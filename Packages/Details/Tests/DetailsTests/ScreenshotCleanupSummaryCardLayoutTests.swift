import XCTest
@testable import Details

final class ScreenshotCleanupSummaryCardLayoutTests: XCTestCase {
    @MainActor
    func testReservedSelectionCountsCoverZeroOneAndMaximumVariants() {
        XCTAssertEqual(
            ScreenshotCleanupSummaryCard.reservedSelectionCounts(assetCount: 0),
            [0]
        )
        XCTAssertEqual(
            ScreenshotCleanupSummaryCard.reservedSelectionCounts(assetCount: 1),
            [0, 1]
        )
        XCTAssertEqual(
            ScreenshotCleanupSummaryCard.reservedSelectionCounts(assetCount: 8),
            [0, 1, 8]
        )
    }
}
