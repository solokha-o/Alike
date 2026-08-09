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

        let completed = await manager.nextClusterToReview(from: [reviewed], reviewStates: states)
        XCTAssertNil(completed)
    }

    func testProgressStaysAvailableWhenEveryClusterIsReviewed() async {
        let repo = MockCleanupSessionRepository()
        let manager = CleanupSessionManager(repository: repo)

        let firstID = UUID()
        let secondID = UUID()
        let clusters = [
            PhotoCluster(id: firstID, assets: []),
            PhotoCluster(id: secondID, assets: [])
        ]

        let states: [UUID: ClusterReviewState] = [
            firstID: ClusterReviewState(
                clusterID: firstID,
                bestShotLocalIdentifier: "best-1",
                selectedLocalIdentifiers: ["a", "b"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 100
            ),
            secondID: ClusterReviewState(
                clusterID: secondID,
                bestShotLocalIdentifier: "best-2",
                selectedLocalIdentifiers: ["c"],
                mode: .selection,
                status: .reviewed,
                estimatedSavingsBytes: 200
            )
        ]

        let next = await manager.nextClusterToReview(from: clusters, reviewStates: states)
        XCTAssertNil(next)

        let progress = await manager.progress(for: clusters, reviewStates: states, activeSession: nil)

        XCTAssertEqual(progress.totalClusters, 2)
        XCTAssertEqual(progress.reviewedCount, 2)
        XCTAssertEqual(progress.remainingClusters, 0)
        XCTAssertEqual(progress.reviewedRatio, 1, accuracy: 0.0001)
        XCTAssertEqual(progress.totalSelectedItems, 3)
        XCTAssertEqual(progress.reviewedSavingsBytes, 300)
    }

    /// A cluster the user finished while keeping several photos — or all of
    /// them — is done, so it must not come back around in the review queue.
    func testConfirmedMultiKeepClustersLeaveTheReviewQueue() async {
        let repo = MockCleanupSessionRepository()
        let manager = CleanupSessionManager(repository: repo)

        let multiKeepID = UUID()
        let keepAllID = UUID()
        let clusters = [
            PhotoCluster(id: multiKeepID, assets: []),
            PhotoCluster(id: keepAllID, assets: [])
        ]

        let states: [UUID: ClusterReviewState] = [
            multiKeepID: ClusterReviewState(
                clusterID: multiKeepID,
                bestShotLocalIdentifier: "best-1",
                selectedLocalIdentifiers: ["a"],
                isReviewConfirmed: true,
                status: .reviewed,
                estimatedSavingsBytes: 100
            ),
            keepAllID: ClusterReviewState(
                clusterID: keepAllID,
                bestShotLocalIdentifier: "best-2",
                selectedLocalIdentifiers: [],
                isReviewConfirmed: true,
                status: .reviewed,
                estimatedSavingsBytes: 0
            )
        ]

        let next = await manager.nextClusterToReview(from: clusters, reviewStates: states)
        XCTAssertNil(next)

        let progress = await manager.progress(for: clusters, reviewStates: states, activeSession: nil)
        XCTAssertEqual(progress.reviewedCount, 2)
        XCTAssertEqual(progress.remainingClusters, 0)
    }
}
