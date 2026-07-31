import XCTest
import Core
@testable import Cleanup

/// The cleanup grid card previews `bestShotAsset(preferring:)`, so clustering
/// order no longer decides which photo represents a cluster.
final class PhotoClusterPreviewAssetTests: XCTestCase {
    func testPrefersReviewedBestShotOverClusteringOrder() {
        let cluster = PhotoCluster(assets: [
            FakePhotoAsset(localIdentifier: "first"),
            FakePhotoAsset(localIdentifier: "chosen")
        ])

        XCTAssertEqual(
            cluster.bestShotAsset(preferring: "chosen")?.localIdentifier,
            "chosen"
        )
    }

    func testFallsBackToComputedBestShotWithoutReviewState() {
        let cluster = PhotoCluster(assets: [
            FakePhotoAsset(localIdentifier: "first"),
            FakePhotoAsset(localIdentifier: "favorite", isFavorite: true)
        ])

        XCTAssertEqual(cluster.bestShotAsset()?.localIdentifier, "favorite")
    }

    func testFallsBackToComputedBestShotWhenPreferredAssetIsMissing() {
        let cluster = PhotoCluster(assets: [
            FakePhotoAsset(localIdentifier: "first"),
            FakePhotoAsset(localIdentifier: "favorite", isFavorite: true)
        ])

        XCTAssertEqual(cluster.bestShotAsset(preferring: "deleted")?.localIdentifier, "favorite")
    }

    func testEmptyClusterHasNoPreviewAsset() {
        XCTAssertNil(PhotoCluster(assets: []).bestShotAsset(preferring: "anything"))
    }
}
