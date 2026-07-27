import XCTest
@testable import Details

final class ClusterReviewSummaryCardLayoutTests: XCTestCase {
    @MainActor
    func testSummaryUsesFixedHeightInHorizontalLayout() {
        XCTAssertEqual(
            ClusterReviewSummaryCard.summaryContentHeight(isAccessibilitySize: false),
            88
        )
    }

    @MainActor
    func testSummaryUsesIntrinsicHeightInAccessibilityLayout() {
        XCTAssertNil(
            ClusterReviewSummaryCard.summaryContentHeight(isAccessibilitySize: true)
        )
    }
}
