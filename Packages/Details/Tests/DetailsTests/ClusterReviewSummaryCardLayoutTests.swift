import XCTest
@testable import Details

final class ClusterReviewSummaryCardLayoutTests: XCTestCase {
    @MainActor
    func testReservedSelectionCountsCoverEverySummaryVariant() {
        XCTAssertEqual(
            ClusterReviewSummaryCard.reservedSelectionCounts(assetCount: 1),
            [0]
        )
        XCTAssertEqual(
            ClusterReviewSummaryCard.reservedSelectionCounts(assetCount: 2),
            [0, 1]
        )
        XCTAssertEqual(
            ClusterReviewSummaryCard.reservedSelectionCounts(assetCount: 8),
            [0, 1, 7]
        )
    }

    @MainActor
    func testReservedReviewStatusesCoverEveryStatusLayout() {
        XCTAssertEqual(
            ClusterReviewSummaryCard.reservedReviewStatuses.map(\.rawValue),
            ["notReviewed", "needsReReview", "inReview", "reviewed"]
        )
    }
}
