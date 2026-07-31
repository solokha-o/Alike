import XCTest
import Photos
import Core
@testable import Cleanup

final class CleanupClusterControlsTests: XCTestCase {
    private let allStatuses: [ClusterReviewStatus] = [.notReviewed, .needsReReview, .inReview, .reviewed]

    // MARK: - CleanupReviewFilter

    func testNeedsReviewFilterMatchesNotReviewedAndNeedsReReview() {
        let filter = CleanupReviewFilter.needsReview

        XCTAssertTrue(filter.matches(.notReviewed))
        XCTAssertTrue(filter.matches(.needsReReview))
        XCTAssertFalse(filter.matches(.inReview))
        XCTAssertFalse(filter.matches(.reviewed))
    }

    func testAllFilterMatchesEveryStatus() {
        for status in allStatuses {
            XCTAssertTrue(CleanupReviewFilter.all.matches(status), "\(status) should match .all")
        }
    }

    func testInReviewAndReviewedFiltersMatchExactlyOneStatus() {
        XCTAssertEqual(allStatuses.filter(CleanupReviewFilter.inReview.matches), [.inReview])
        XCTAssertEqual(allStatuses.filter(CleanupReviewFilter.reviewed.matches), [.reviewed])
    }

    // MARK: - CleanupClusterControls composition

    func testDefaultControlsMatchClusterInEveryReviewStatus() {
        let controls = CleanupClusterControls()
        let cluster = PhotoCluster(assets: [FakePhotoAsset(), FakePhotoAsset()])

        for status in allStatuses {
            XCTAssertTrue(controls.matches(cluster, reviewStatus: status), "\(status) should pass default controls")
        }
    }

    func testMinimumClusterSizeRejectsUndersizedClusterDespiteMatchingReviewStatus() {
        var controls = CleanupClusterControls()
        controls.reviewFilter = .needsReview
        controls.minimumClusterSize = .three

        let small = PhotoCluster(assets: [FakePhotoAsset(), FakePhotoAsset()])
        let large = PhotoCluster(assets: [FakePhotoAsset(), FakePhotoAsset(), FakePhotoAsset()])

        XCTAssertFalse(controls.matches(small, reviewStatus: .notReviewed))
        XCTAssertTrue(controls.matches(large, reviewStatus: .notReviewed))
    }

    func testFavoritesOnlyRejectsClusterWithoutFavoriteAssets() {
        var controls = CleanupClusterControls()
        controls.favoritesOnly = true

        let withoutFavorite = PhotoCluster(assets: [FakePhotoAsset(), FakePhotoAsset()])
        let withFavorite = PhotoCluster(assets: [FakePhotoAsset(), FakePhotoAsset(isFavorite: true)])

        XCTAssertFalse(controls.matches(withoutFavorite, reviewStatus: .notReviewed))
        XCTAssertTrue(controls.matches(withFavorite, reviewStatus: .notReviewed))
    }
}
