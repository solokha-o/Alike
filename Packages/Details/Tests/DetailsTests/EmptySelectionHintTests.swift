import Core
import XCTest
@testable import Details

/// The card must not say "tap photos" while a tap cannot select anything.
final class EmptySelectionHintTests: XCTestCase {
    func testUnresolvedClusterNamesTheStepThatUnlocksSelection() {
        XCTAssertEqual(
            ClusterReviewSummaryCard.emptySelectionHint(bestShotConfidence: .unresolved),
            DetailsL10n.ClusterReviewSummaryCard.touchAndHoldToChooseBestShot
        )
    }

    func testClusterWithABestShotKeepsTheTapHint() {
        for confidence in [BestShotConfidence.automatic, .lowConfidence] {
            XCTAssertEqual(
                ClusterReviewSummaryCard.emptySelectionHint(bestShotConfidence: confidence),
                DetailsL10n.ClusterReviewSummaryCard.tapPhotosSelectThemCleanup
            )
        }
    }
}
