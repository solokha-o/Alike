import SwiftUI
import Foundation
import Testing
@testable import Details

struct ScreenshotCleanupSummaryCardLayoutTests {
    @MainActor
    @Test func testReservedSelectionCountsCoverZeroOneAndMaximumVariants() {
        #expect(ScreenshotCleanupSummaryCard.reservedSelectionCounts(assetCount: 0) == [0])
        #expect(ScreenshotCleanupSummaryCard.reservedSelectionCounts(assetCount: 1) == [0, 1])
        #expect(ScreenshotCleanupSummaryCard.reservedSelectionCounts(assetCount: 8) == [0, 1, 8])
    }

    /// The selection line reserves every count, so selecting screenshots
    /// never reflows the card above the grid.
    @MainActor
    @Test func testCardHeightIsStableAcrossSelection() {
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

        #expect(heights[0] > 0)
        #expect(Set(heights).count == 1, "Card height changed with the selection: \(heights)")
    }
}
