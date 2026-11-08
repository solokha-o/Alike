import Foundation
import Testing
import Photos
import Core
@testable import Cleanup

struct CleanupClusterControlsTests {
    private let allStatuses: [ClusterReviewStatus] = [.notReviewed, .needsReReview, .inReview, .reviewed]

    // MARK: - CleanupReviewFilter

    @Test func testNeedsReviewFilterMatchesNotReviewedAndNeedsReReview() {
        let filter = CleanupReviewFilter.needsReview

        #expect(filter.matches(.notReviewed))
        #expect(filter.matches(.needsReReview))
        #expect(!filter.matches(.inReview))
        #expect(!filter.matches(.reviewed))
    }

    @Test func testAllFilterMatchesEveryStatus() {
        for status in allStatuses {
            #expect(CleanupReviewFilter.all.matches(status), "\(status) should match .all")
        }
    }

    @Test func testInReviewAndReviewedFiltersMatchExactlyOneStatus() {
        #expect(allStatuses.filter(CleanupReviewFilter.inReview.matches) == [.inReview])
        #expect(allStatuses.filter(CleanupReviewFilter.reviewed.matches) == [.reviewed])
    }

    // MARK: - CleanupClusterControls composition

    @Test func testDefaultControlsMatchClusterInEveryReviewStatus() {
        let controls = CleanupClusterControls()
        let cluster = PhotoCluster(assets: [FakePhotoAsset(), FakePhotoAsset()])

        for status in allStatuses {
            #expect(controls.matches(cluster, reviewStatus: status), "\(status) should pass default controls")
        }
    }

    @Test func testMinimumClusterSizeRejectsUndersizedClusterDespiteMatchingReviewStatus() {
        var controls = CleanupClusterControls()
        controls.reviewFilter = .needsReview
        controls.minimumClusterSize = .three

        let small = PhotoCluster(assets: [FakePhotoAsset(), FakePhotoAsset()])
        let large = PhotoCluster(assets: [FakePhotoAsset(), FakePhotoAsset(), FakePhotoAsset()])

        #expect(!controls.matches(small, reviewStatus: .notReviewed))
        #expect(controls.matches(large, reviewStatus: .notReviewed))
    }

    @Test func testFavoritesOnlyRejectsClusterWithoutFavoriteAssets() {
        var controls = CleanupClusterControls()
        controls.favoritesOnly = true

        let withoutFavorite = PhotoCluster(assets: [FakePhotoAsset(), FakePhotoAsset()])
        let withFavorite = PhotoCluster(assets: [FakePhotoAsset(), FakePhotoAsset(isFavorite: true)])

        #expect(!controls.matches(withoutFavorite, reviewStatus: .notReviewed))
        #expect(controls.matches(withFavorite, reviewStatus: .notReviewed))
    }
}
