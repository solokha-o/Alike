import CleanupWorkspace
import Core
import Foundation
import Photos
import Testing
import WidgetSupport
@testable import Alike

/// Pins the extra-large widget's rows to the headline figure above them. Both must use
/// one keeper per group: a row that counts the keeper promises bytes the app will never
/// delete. The byte source is held by the type `WidgetSnapshotPublisher` builds a row from,
/// because every source gives a fake asset the same bytes.
///
/// `WidgetClusterSummary.top` has its own ranking tests in `WidgetSupport`. These cover
/// the half that lives in the app target, where the rows are built from clusters.
@MainActor
@Suite struct WidgetTopClustersTests {
    /// The user picks a smaller photo than the computed best shot. If both picks were
    /// the same asset, this test could not see the user's choice get lost.
    @Test func testRowLeavesOutTheKeeperTheUserChose() {
        let cluster = PhotoCluster(assets: [
            WidgetFakeAsset("chosen-first", bytes: 1_000_000),
            WidgetFakeAsset("chosen-keeper", bytes: 500_000),
            WidgetFakeAsset("chosen-third", bytes: 2_000_000)
        ])
        #expect(cluster.bestShotAsset()?.localIdentifier != "chosen-keeper")

        let rows = WidgetSnapshotPublisher.topClusters(
            [cluster],
            reviewStates: [cluster.id: keeperState(cluster, keeper: "chosen-keeper")]
        )

        #expect(rows == [WidgetClusterSummary(reclaimableBytes: 3_000_000, photoCount: 3)])
    }

    /// No review state yet: the computed best shot is the keeper. The cluster's total
    /// minus that one asset fails if the keeper is counted, whichever asset wins.
    @Test func testRowLeavesOutTheComputedKeeperWithoutAReviewState() throws {
        let cluster = PhotoCluster(assets: [
            WidgetFakeAsset("computed-first", bytes: 1_000_000),
            WidgetFakeAsset("computed-second", bytes: 2_000_000)
        ])
        let keeper = try #require(cluster.bestShotAsset())

        let rows = WidgetSnapshotPublisher.topClusters([cluster], reviewStates: [:])

        #expect(rows.map(\.reclaimableBytes) == [3_000_000 - keeper.estimatedCleanupBytes])
    }

    /// A group of one is all keeper, so it frees nothing and gets no row.
    @Test func testGroupThatIsOnlyItsKeeperHasNoRow() {
        let cluster = PhotoCluster(assets: [WidgetFakeAsset("alone", bytes: 1_000_000)])

        #expect(WidgetSnapshotPublisher.topClusters([cluster], reviewStates: [:]).isEmpty)
    }

    /// With no shared asset and no category, nothing separates the two figures, so the
    /// rows must add up to the headline exactly. The second keeper is stale: it left the
    /// group, so both sides must fall back to the computed pick.
    @Test func testRowsAddUpToTheHeadlineWhenNothingOverlaps() {
        let chosen = PhotoCluster(assets: [
            WidgetFakeAsset("sum-a1", bytes: 1_000_000),
            WidgetFakeAsset("sum-a2", bytes: 2_000_000)
        ])
        let stale = PhotoCluster(assets: [
            WidgetFakeAsset("sum-b1", bytes: 700_000),
            WidgetFakeAsset("sum-b2", bytes: 300_000),
            WidgetFakeAsset("sum-b3", bytes: 500_000)
        ])
        #expect(chosen.bestShotAsset()?.localIdentifier != "sum-a1")
        let reviewStates = [
            chosen.id: keeperState(chosen, keeper: "sum-a1"),
            stale.id: keeperState(stale, keeper: "sum-gone")
        ]

        let rows = WidgetSnapshotPublisher.topClusters([chosen, stale], reviewStates: reviewStates)
        let headline = headlineEstimate([chosen, stale], reviewStates: reviewStates)

        #expect(rows.count == 2)
        #expect(rows.reduce(into: Int64(0)) { $0 += $1.reclaimableBytes } == headline.totalBytes)
    }

    /// A shared asset is one asset to the headline and appears in both rows, which is
    /// why the rows are never added up in the widget. Each row must still fit inside
    /// the headline: a row larger than it is the disagreement a user can see.
    @Test func testNoRowExceedsTheHeadlineWhenGroupsShareAnAsset() {
        let shared = WidgetFakeAsset("shared", bytes: 4_000_000)
        let first = PhotoCluster(assets: [WidgetFakeAsset("keep-1", bytes: 2_000_000), shared])
        let second = PhotoCluster(assets: [WidgetFakeAsset("keep-2", bytes: 3_000_000), shared])
        #expect(first.bestShotAsset()?.localIdentifier != "keep-1")
        #expect(second.bestShotAsset()?.localIdentifier != "keep-2")
        let reviewStates = [
            first.id: keeperState(first, keeper: "keep-1"),
            second.id: keeperState(second, keeper: "keep-2")
        ]

        let rows = WidgetSnapshotPublisher.topClusters([first, second], reviewStates: reviewStates)
        let headline = headlineEstimate([first, second], reviewStates: reviewStates)

        #expect(rows.map(\.reclaimableBytes) == [4_000_000, 4_000_000])
        #expect(headline.clusterBytes == 4_000_000)
    }

    /// The figure the scanner card and the widget headline read, through its real entry.
    private func headlineEstimate(
        _ clusters: [PhotoCluster],
        reviewStates: [UUID: ClusterReviewState]
    ) -> ReclaimableEstimate {
        CleanupWorkspaceContent(
            clusters: clusters,
            categories: [],
            reviewStates: reviewStates,
            resurfacingStates: [:],
            activeSession: nil,
            insights: .empty,
            hasCompletedScanBaseline: true,
            shouldShowRescanPrompt: false
        ).reclaimableEstimate()
    }

    private func keeperState(_ cluster: PhotoCluster, keeper: String) -> ClusterReviewState {
        ClusterReviewState(
            clusterID: cluster.id,
            bestShotLocalIdentifier: keeper,
            isBestShotUserSelected: true,
            selectedLocalIdentifiers: [],
            status: .inReview,
            estimatedSavingsBytes: 0
        )
    }
}

/// `PHAsset` has no public initializer. `AssetByteSize` gives a subclass from outside
/// Photos the pixel heuristic, `width * height / 2`, and never touches its cache.
private final class WidgetFakeAsset: PHAsset, @unchecked Sendable {
    private let identifier: String
    private let bytes: Int

    init(_ identifier: String, bytes: Int) {
        self.identifier = identifier
        self.bytes = bytes
        super.init()
    }

    override var localIdentifier: String { identifier }
    override var pixelWidth: Int { bytes * 2 }
    override var pixelHeight: Int { 1 }
}
