import Core
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

    /// The Best Shot summary reserves its reason line with every reason code
    /// joined together, so that line's height never depends on whether the
    /// resolved cluster's own reason codes are empty, one, or many — the
    /// scenario behind the summary card resizing when the foreign-edit note
    /// or the reason line comes and goes.
    @MainActor
    func testReservedBestShotReasonTextCoversEveryReasonCombination() {
        let reserved = ClusterReviewSummaryCard.reservedBestShotReasonText

        for code in BestShotReasonCode.allCases {
            let single = BestShotReasonSummary.text(for: [code]) ?? ""
            XCTAssertTrue(
                reserved.contains(single),
                "Reservation text is missing the '\(code)' reason, so that reason could render taller than the space held for it."
            )
        }

        XCTAssertEqual(
            reserved,
            BestShotReasonSummary.text(for: BestShotReasonCode.allCases),
            "Reservation should be exactly every reason code joined, the longest line any real cluster can produce."
        )
    }
}
