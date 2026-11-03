import Core
import Foundation
import Testing
@testable import Details

/// The card must not say "tap photos" while a tap cannot select anything.
@Suite struct EmptySelectionHintTests {
    @Test func testUnresolvedClusterNamesTheStepThatUnlocksSelection() {
        #expect(ClusterReviewSummaryCard.emptySelectionHint(bestShotConfidence: .unresolved) == DetailsL10n.ClusterReviewSummaryCard.touchAndHoldToChooseBestShot)
    }

    @Test func testClusterWithABestShotKeepsTheTapHint() {
        for confidence in [BestShotConfidence.automatic, .lowConfidence] {
            #expect(ClusterReviewSummaryCard.emptySelectionHint(bestShotConfidence: confidence) == DetailsL10n.ClusterReviewSummaryCard.tapPhotosSelectThemCleanup)
        }
    }
}
