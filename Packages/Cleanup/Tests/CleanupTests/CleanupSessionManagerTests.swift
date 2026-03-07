import XCTest
import Core
@testable import Cleanup

final class CleanupSessionManagerTests: XCTestCase {
    func testProgressIncludesSelectedItemsAndRemainingClusters() async {
        let repo = MockCleanupSessionRepository()
        let manager = CleanupSessionManager(repository: repo)

        let reviewedID = UUID()
        let inReviewID = UUID()
        let clusters = [
            PhotoCluster(id: reviewedID, assets: []),
            PhotoCluster(id: inReviewID, assets: []),
            PhotoCluster(assets: [])
        ]

        let states: [UUID: ClusterReviewState] = [
            reviewedID: ClusterReviewState(
                clusterID: reviewedID,
                bestShotLocalIdentifier: "best-1",
                selectedLocalIdentifiers: ["a", "b"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 100
            ),
            inReviewID: ClusterReviewState(
                clusterID: inReviewID,
                bestShotLocalIdentifier: "best-2",
                selectedLocalIdentifiers: ["c"],
                mode: .selection,
                status: .inReview,
                estimatedSavingsBytes: 200
            )
        ]

        let progress = await manager.progress(for: clusters, reviewStates: states, activeSession: nil)

        XCTAssertEqual(progress.totalClusters, 3)
        XCTAssertEqual(progress.reviewedCount, 1)
        XCTAssertEqual(progress.inReviewCount, 1)
        XCTAssertEqual(progress.notReviewedCount, 1)
        XCTAssertEqual(progress.reviewedSavingsBytes, 300)
        XCTAssertEqual(progress.totalSelectedItems, 3)
        XCTAssertEqual(progress.remainingClusters, 2)
    }

    func testNextClusterToReviewPrefersNotReviewedThenInReview() async {
        let repo = MockCleanupSessionRepository()
        let manager = CleanupSessionManager(repository: repo)

        let reviewedID = UUID()
        let inReviewID = UUID()
        let notReviewedID = UUID()

        let reviewed = PhotoCluster(id: reviewedID, assets: [])
        let inReview = PhotoCluster(id: inReviewID, assets: [])
        let notReviewed = PhotoCluster(id: notReviewedID, assets: [])

        let states: [UUID: ClusterReviewState] = [
            reviewedID: ClusterReviewState(
                clusterID: reviewedID,
                bestShotLocalIdentifier: "best-1",
                selectedLocalIdentifiers: ["a"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 100
            ),
            inReviewID: ClusterReviewState(
                clusterID: inReviewID,
                bestShotLocalIdentifier: "best-2",
                selectedLocalIdentifiers: ["b"],
                mode: .selection,
                status: .inReview,
                estimatedSavingsBytes: 50
            )
        ]

        let first = await manager.nextClusterToReview(from: [reviewed, inReview, notReviewed], reviewStates: states)
        XCTAssertEqual(first?.id, notReviewedID)

        let second = await manager.nextClusterToReview(from: [reviewed, inReview], reviewStates: states)
        XCTAssertEqual(second?.id, inReviewID)
    }
}
