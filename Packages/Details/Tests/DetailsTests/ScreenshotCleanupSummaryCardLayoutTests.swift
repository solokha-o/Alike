import SwiftUI
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

    /// The selection line reserves every count, so selecting screenshots
    /// never reflows the card above the grid.
    @MainActor
    func testCardHeightIsStableAcrossSelection() {
        let heights = ScreenshotCleanupSummaryCard.reservedSelectionCounts(assetCount: 8).map { count in
            ClusterReviewSummaryCardLayoutTests.fittingHeight(
                of: ScreenshotCleanupSummaryCard(
                    category: .screenshots,
                    assetCount: 8,
                    selectedCount: count,
                    estimatedSavingsText: "12 MB",
                    maximumEstimatedSavingsText: "84 MB"
                )
            )
        }

        XCTAssertGreaterThan(heights[0], 0)
        XCTAssertEqual(Set(heights).count, 1, "Card height changed with the selection: \(heights)")
    }
}
