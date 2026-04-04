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
        XCTAssertEqual(progress.needsReReviewCount, 0)
        XCTAssertEqual(progress.inReviewCount, 1)
        XCTAssertEqual(progress.notReviewedCount, 1)
        XCTAssertEqual(progress.reviewedSavingsBytes, 300)
        XCTAssertEqual(progress.totalSelectedItems, 3)
        XCTAssertEqual(progress.remainingClusters, 2)
    }

    func testProgressExcludesNeedsReReviewFromSavedSelections() async {
        let repo = MockCleanupSessionRepository()
        let manager = CleanupSessionManager(repository: repo)

        let needsReviewID = UUID()
        let reviewedID = UUID()
        let clusters = [
            PhotoCluster(id: needsReviewID, assets: []),
            PhotoCluster(id: reviewedID, assets: [])
        ]

        let states: [UUID: ClusterReviewState] = [
            needsReviewID: ClusterReviewState(
                clusterID: needsReviewID,
                bestShotLocalIdentifier: "best-1",
                selectedLocalIdentifiers: ["a", "b"],
                mode: .selection,
                status: .needsReReview,
                estimatedSavingsBytes: 100,
                resurfacingState: .changed
            ),
            reviewedID: ClusterReviewState(
                clusterID: reviewedID,
                bestShotLocalIdentifier: "best-2",
                selectedLocalIdentifiers: ["c"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 200
            )
        ]

        let progress = await manager.progress(for: clusters, reviewStates: states, activeSession: nil)

        XCTAssertEqual(progress.reviewedCount, 1)
        XCTAssertEqual(progress.needsReReviewCount, 1)
        XCTAssertEqual(progress.totalSelectedItems, 1)
        XCTAssertEqual(progress.reviewedSavingsBytes, 200)
        XCTAssertEqual(progress.remainingClusters, 1)
    }

    func testNextClusterToReviewPrefersNeedsReReviewThenNotReviewedThenInReview() async {
        let repo = MockCleanupSessionRepository()
        let manager = CleanupSessionManager(repository: repo)

        let needsReviewID = UUID()
        let reviewedID = UUID()
        let inReviewID = UUID()
        let notReviewedID = UUID()

        let needsReview = PhotoCluster(id: needsReviewID, assets: [])
        let reviewed = PhotoCluster(id: reviewedID, assets: [])
        let inReview = PhotoCluster(id: inReviewID, assets: [])
        let notReviewed = PhotoCluster(id: notReviewedID, assets: [])

        let states: [UUID: ClusterReviewState] = [
            needsReviewID: ClusterReviewState(
                clusterID: needsReviewID,
                bestShotLocalIdentifier: "best-0",
                selectedLocalIdentifiers: [],
                mode: .selection,
                status: .needsReReview,
                estimatedSavingsBytes: 0,
                resurfacingState: .new
            ),
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

        let first = await manager.nextClusterToReview(
            from: [reviewed, inReview, notReviewed, needsReview],
            reviewStates: states
        )
        XCTAssertEqual(first?.id, needsReviewID)

        let second = await manager.nextClusterToReview(
            from: [reviewed, inReview, notReviewed],
            reviewStates: states
        )
        XCTAssertEqual(second?.id, notReviewedID)

        let third = await manager.nextClusterToReview(from: [reviewed, inReview], reviewStates: states)
        XCTAssertEqual(third?.id, inReviewID)
    }
}
