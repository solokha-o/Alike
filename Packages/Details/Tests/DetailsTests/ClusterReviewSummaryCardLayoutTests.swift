import XCTest
@testable import Details

final class ClusterReviewSummaryCardLayoutTests: XCTestCase {
    @MainActor
    func testSummaryUsesMinimumHeight() {
        XCTAssertEqual(
            ClusterReviewSummaryCard.summaryContentMinimumHeight,
            88
        )
    }
}
