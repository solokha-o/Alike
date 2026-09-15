import XCTest
@testable import Core

/// The reclaimable figure counts every asset once and never counts a keeper.
final class ReclaimableEstimateCalculatorTests: XCTestCase {
    func testEmptyInputIsZero() {
        XCTAssertEqual(ReclaimableEstimateCalculator.estimate(clusters: [], categories: []), .zero)
    }

    func testKeeperIsExcludedFromClusterBytes() {
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [cluster(["keep": 100, "a": 10, "b": 20], keeper: "keep")],
            categories: []
        )

        XCTAssertEqual(estimate.clusterBytes, 30)
        XCTAssertEqual(estimate.categoryBytes, 0)
        XCTAssertEqual(estimate.totalBytes, 30)
    }

    func testClusterWithoutKeeperCountsEveryAsset() {
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [cluster(["a": 10, "b": 20], keeper: nil)],
            categories: []
        )

        XCTAssertEqual(estimate.totalBytes, 30)
    }

    func testAssetInClusterAndCategoryIsCountedOnce() {
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [cluster(["keep": 100, "shot": 40, "b": 20], keeper: "keep")],
            categories: [category(["shot", "other"], bytes: 40 + 15)]
        )

        XCTAssertEqual(estimate.clusterBytes, 60)
        XCTAssertEqual(estimate.categoryBytes, 15)
        XCTAssertEqual(estimate.totalBytes, 75)
    }

    func testKeeperThatIsAlsoACategoryCandidateStaysInTheCategory() {
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [cluster(["shot": 40, "b": 20], keeper: "shot")],
            categories: [category(["shot"], bytes: 40)]
        )

        XCTAssertEqual(estimate.clusterBytes, 20)
        XCTAssertEqual(estimate.categoryBytes, 40)
        XCTAssertEqual(estimate.totalBytes, 60)
    }

    func testAssetInTwoClustersIsCountedOnce() {
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [
                cluster(["k1": 1, "dup": 30], keeper: "k1"),
                cluster(["k2": 1, "dup": 30, "c": 5], keeper: "k2")
            ],
            categories: []
        )

        XCTAssertEqual(estimate.totalBytes, 35)
    }

    func testCategoriesAloneUseTheirRecordedSum() {
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [],
            categories: [category(["s1", "s2"], bytes: 700), category(["b1"], bytes: 400)]
        )

        XCTAssertEqual(estimate.clusterBytes, 0)
        XCTAssertEqual(estimate.categoryBytes, 1_100)
    }

    func testCategoryNeverGoesBelowZeroWhenRecordedSumIsStale() {
        // The category recorded a smaller sum than the cluster now reports for the
        // same asset; the overlap is still subtracted, but only down to zero.
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [cluster(["keep": 1, "shot": 90], keeper: "keep")],
            categories: [category(["shot"], bytes: 50)]
        )

        XCTAssertEqual(estimate.clusterBytes, 90)
        XCTAssertEqual(estimate.categoryBytes, 0)
    }

    private func cluster(_ bytes: KeyValuePairs<String, Int64>, keeper: String?) -> ReclaimableCluster {
        ReclaimableCluster(
            assets: bytes.map { ReclaimableAsset(localIdentifier: $0.key, estimatedCleanupBytes: $0.value) },
            keeperLocalIdentifier: keeper
        )
    }

    private func category(_ identifiers: [String], bytes: Int64) -> ReclaimableCategory {
        ReclaimableCategory(localIdentifiers: identifiers, estimatedSavingsBytes: bytes)
    }
}
