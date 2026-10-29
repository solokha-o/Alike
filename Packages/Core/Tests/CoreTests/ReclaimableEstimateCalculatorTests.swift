import Foundation
import Testing
@testable import Core

/// The reclaimable figure counts every asset once and never counts a keeper.
@Suite struct ReclaimableEstimateCalculatorTests {
    @Test func testEmptyInputIsZero() {
        #expect(ReclaimableEstimateCalculator.estimate(clusters: [], categories: []) == .zero)
    }

    @Test func testKeeperIsExcludedFromClusterBytes() {
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [cluster(["keep": 100, "a": 10, "b": 20], keeper: "keep")],
            categories: []
        )

        #expect(estimate.clusterBytes == 30)
        #expect(estimate.categoryBytes == 0)
        #expect(estimate.totalBytes == 30)
    }

    @Test func testClusterWithoutKeeperCountsEveryAsset() {
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [cluster(["a": 10, "b": 20], keeper: nil)],
            categories: []
        )

        #expect(estimate.totalBytes == 30)
    }

    @Test func testAssetInClusterAndCategoryIsCountedOnce() {
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [cluster(["keep": 100, "shot": 40, "b": 20], keeper: "keep")],
            categories: [category(["shot", "other"], bytes: 40 + 15)]
        )

        #expect(estimate.clusterBytes == 60)
        #expect(estimate.categoryBytes == 15)
        #expect(estimate.totalBytes == 75)
    }

    @Test func testKeeperThatIsAlsoACategoryCandidateStaysInTheCategory() {
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [cluster(["shot": 40, "b": 20], keeper: "shot")],
            categories: [category(["shot"], bytes: 40)]
        )

        #expect(estimate.clusterBytes == 20)
        #expect(estimate.categoryBytes == 40)
        #expect(estimate.totalBytes == 60)
    }

    @Test func testAssetInTwoClustersIsCountedOnce() {
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [
                cluster(["k1": 1, "dup": 30], keeper: "k1"),
                cluster(["k2": 1, "dup": 30, "c": 5], keeper: "k2")
            ],
            categories: []
        )

        #expect(estimate.totalBytes == 35)
    }

    @Test func testCategoriesAloneUseTheirRecordedSum() {
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [],
            categories: [category(["s1", "s2"], bytes: 700), category(["b1"], bytes: 400)]
        )

        #expect(estimate.clusterBytes == 0)
        #expect(estimate.categoryBytes == 1_100)
    }

    @Test func testCategoryNeverGoesBelowZeroWhenRecordedSumIsStale() {
        // The category recorded a smaller sum than the cluster now reports for the
        // same asset; the overlap is still subtracted, but only down to zero.
        let estimate = ReclaimableEstimateCalculator.estimate(
            clusters: [cluster(["keep": 1, "shot": 90], keeper: "keep")],
            categories: [category(["shot"], bytes: 50)]
        )

        #expect(estimate.clusterBytes == 90)
        #expect(estimate.categoryBytes == 0)
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
