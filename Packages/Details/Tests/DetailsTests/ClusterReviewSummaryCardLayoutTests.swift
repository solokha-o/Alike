import Core
import SwiftUI
import UIKit
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

    /// The status pill reserves every status's wording and icon, so changing
    /// the review status never changes the card's height.
    @MainActor
    func testCardHeightIsStableAcrossEveryReviewStatus() {
        // At 320 pt a shorter status lets `ViewThatFits` keep the single-row
        // header that a longer one cannot, so without the reservation the
        // card's height follows the status.
        for width in [390, 320] as [CGFloat] {
            let heights = ClusterReviewSummaryCard.reservedReviewStatuses.map { status in
                Self.fittingHeight(of: Self.card(reviewStatus: status), width: width)
            }

            XCTAssertGreaterThan(heights[0], 0)
            XCTAssertEqual(
                Set(heights).count,
                1,
                "Card height changed with the review status at width \(width): \(heights)"
            )
        }
    }

    /// The selection line reserves every count and both review wordings, so
    /// selecting photos or finishing the review never reflows the card.
    @MainActor
    func testCardHeightIsStableAcrossSelectionAndConfirmation() {
        var heights: [CGFloat] = []
        for count in ClusterReviewSummaryCard.reservedSelectionCounts(assetCount: 8) {
            for confirmed in [false, true] {
                heights.append(
                    Self.fittingHeight(
                        of: Self.card(assetCount: 8, selectedCount: count, isReviewConfirmed: confirmed)
                    )
                )
            }
        }

        XCTAssertGreaterThan(heights[0], 0)
        XCTAssertEqual(Set(heights).count, 1, "Card height changed with the selection: \(heights)")
    }

    @MainActor
    private static func card(
        assetCount: Int = 8,
        selectedCount: Int = 0,
        reviewStatus: ClusterReviewStatus = .notReviewed,
        isReviewConfirmed: Bool = false
    ) -> ClusterReviewSummaryCard {
        ClusterReviewSummaryCard(
            assetCount: assetCount,
            bestShotLabel: "Best shot",
            bestShotConfidence: .automatic,
            bestShotReasonCodes: [.sharper],
            selectedCount: selectedCount,
            estimatedSavingsText: "12 MB",
            maximumEstimatedSavingsText: "84 MB",
            reviewStatus: reviewStatus,
            isReviewConfirmed: isReviewConfirmed,
            alikeReactionCue: nil,
            bestShotCelebrationCue: nil,
            onBestShotCelebrationDismissed: { _ in }
        )
    }

    @MainActor
    static func fittingHeight(of view: some View, width: CGFloat = 390) -> CGFloat {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            .height
    }
}
