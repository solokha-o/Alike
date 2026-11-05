import Foundation
import Testing
@testable import Details

/// The hint has to say what a double tap does to the photos: reopening, keeping
/// every photo, or keeping the photos the user did not select.
@Suite struct ClusterReviewToggleTests {
    @Test func testConfirmedReviewOffersToReopen() {
        for selectedCount in [0, 2] {
            #expect(ClusterReviewToggle.hint(isConfirmed: true, selectedCount: selectedCount) == DetailsL10n.ClusterDetails.doubleTapReopenThisCluster)
        }
    }

    @Test func testOpenReviewWithoutSelectionKeepsEveryPhoto() {
        #expect(ClusterReviewToggle.hint(isConfirmed: false, selectedCount: 0) == DetailsL10n.ClusterDetails.finishesReviewKeepsEveryPhoto)
    }

    @Test func testOpenReviewWithSelectionKeepsTheRest() {
        #expect(ClusterReviewToggle.hint(isConfirmed: false, selectedCount: 2) == DetailsL10n.ClusterDetails.finishesReviewKeepsPhotosDid)
    }
}
