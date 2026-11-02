import XCTest
@testable import Details

/// The hint has to say what a double tap does to the photos: reopening, keeping
/// every photo, or keeping the photos the user did not select.
final class ClusterReviewToggleTests: XCTestCase {
    func testConfirmedReviewOffersToReopen() {
        for selectedCount in [0, 2] {
            XCTAssertEqual(
                ClusterReviewToggle.hint(isConfirmed: true, selectedCount: selectedCount),
                DetailsL10n.ClusterDetails.doubleTapReopenThisCluster
            )
        }
    }

    func testOpenReviewWithoutSelectionKeepsEveryPhoto() {
        XCTAssertEqual(
            ClusterReviewToggle.hint(isConfirmed: false, selectedCount: 0),
            DetailsL10n.ClusterDetails.finishesReviewKeepsEveryPhoto
        )
    }

    func testOpenReviewWithSelectionKeepsTheRest() {
        XCTAssertEqual(
            ClusterReviewToggle.hint(isConfirmed: false, selectedCount: 2),
            DetailsL10n.ClusterDetails.finishesReviewKeepsPhotosDid
        )
    }
}
