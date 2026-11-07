import Foundation
import Testing
import Core
@testable import CleanupWorkspace

@Suite struct CleanupSessionManagerTests {
    @Test func testProgressIncludesSelectedItemsAndRemainingClusters() {
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

        let progress = manager.progress(for: clusters, reviewStates: states, activeSession: nil)

        #expect(progress.totalClusters == 3)
        #expect(progress.reviewedCount == 1)
        #expect(progress.needsReReviewCount == 0)
        #expect(progress.inReviewCount == 1)
        #expect(progress.notReviewedCount == 1)
        #expect(progress.reviewedSavingsBytes == 300)
        #expect(progress.totalSelectedItems == 3)
        #expect(progress.remainingClusters == 2)
    }

    @Test func testProgressExcludesNeedsReReviewFromSavedSelections() {
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

        let progress = manager.progress(for: clusters, reviewStates: states, activeSession: nil)

        #expect(progress.reviewedCount == 1)
        #expect(progress.needsReReviewCount == 1)
        #expect(progress.totalSelectedItems == 1)
        #expect(progress.reviewedSavingsBytes == 200)
        #expect(progress.remainingClusters == 1)
    }

    @Test func testNextClusterToReviewPrefersNeedsReReviewThenNotReviewedThenInReview() {
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

        let first = manager.nextClusterToReview(
            from: [reviewed, inReview, notReviewed, needsReview],
            reviewStates: states
        )
        #expect(first?.id == needsReviewID)

        let second = manager.nextClusterToReview(
            from: [reviewed, inReview, notReviewed],
            reviewStates: states
        )
        #expect(second?.id == notReviewedID)

        let third = manager.nextClusterToReview(from: [reviewed, inReview], reviewStates: states)
        #expect(third?.id == inReviewID)

        let completed = manager.nextClusterToReview(from: [reviewed], reviewStates: states)
        #expect(completed == nil)
    }

    @Test func testProgressStaysAvailableWhenEveryClusterIsReviewed() {
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

        let next = manager.nextClusterToReview(from: clusters, reviewStates: states)
        #expect(next == nil)

        let progress = manager.progress(for: clusters, reviewStates: states, activeSession: nil)

        #expect(progress.totalClusters == 2)
        #expect(progress.reviewedCount == 2)
        #expect(progress.remainingClusters == 0)
        #expect(abs(progress.reviewedRatio - 1) <= 0.0001)
        #expect(progress.totalSelectedItems == 3)
        #expect(progress.reviewedSavingsBytes == 300)
    }

    /// A cluster the user finished while keeping several photos — or all of
    /// them — is done, so it must not come back around in the review queue.
    @Test func testConfirmedMultiKeepClustersLeaveTheReviewQueue() {
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

        let next = manager.nextClusterToReview(from: clusters, reviewStates: states)
        #expect(next == nil)

        let progress = manager.progress(for: clusters, reviewStates: states, activeSession: nil)
        #expect(progress.reviewedCount == 2)
        #expect(progress.remainingClusters == 0)
    }
}
