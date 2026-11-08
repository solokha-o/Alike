import Foundation
import Testing
import Core
@testable import Cleanup

/// The cleanup grid card previews `bestShotAsset(preferring:)`, so clustering
/// order no longer decides which photo represents a cluster.
struct PhotoClusterPreviewAssetTests {
    @Test func testPrefersReviewedBestShotOverClusteringOrder() {
        let cluster = PhotoCluster(assets: [
            FakePhotoAsset(localIdentifier: "first"),
            FakePhotoAsset(localIdentifier: "chosen"),
        ])

        #expect(cluster.bestShotAsset(preferring: "chosen")?.localIdentifier == "chosen")
    }

    @Test func testFallsBackToComputedBestShotWithoutReviewState() {
        let cluster = PhotoCluster(assets: [
            FakePhotoAsset(localIdentifier: "first"),
            FakePhotoAsset(localIdentifier: "favorite", isFavorite: true),
        ])

        #expect(cluster.bestShotAsset()?.localIdentifier == "favorite")
    }

    @Test func testFallsBackToComputedBestShotWhenPreferredAssetIsMissing() {
        let cluster = PhotoCluster(assets: [
            FakePhotoAsset(localIdentifier: "first"),
            FakePhotoAsset(localIdentifier: "favorite", isFavorite: true),
        ])

        #expect(cluster.bestShotAsset(preferring: "deleted")?.localIdentifier == "favorite")
    }

    @Test func testEmptyClusterHasNoPreviewAsset() {
        #expect(PhotoCluster(assets: []).bestShotAsset(preferring: "anything") == nil)
    }
}
