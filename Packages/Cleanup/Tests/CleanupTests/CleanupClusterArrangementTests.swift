import Core
import Foundation
import Photos
import Testing
@testable import Cleanup

struct CleanupClusterArrangementTests {
    // MARK: - Content identity

    /// Regression guard for the scroll reset after deleting photos: reconciliation
    /// rebuilds every `PhotoCluster` with a fresh `id`, so view identity has to come
    /// from the cluster's contents instead.
    @Test func testContentKeyIsStableAcrossRegeneratedUUIDs() {
        let assets = [FakePhotoAsset(localIdentifier: "a"), FakePhotoAsset(localIdentifier: "b")]
        let before = PhotoCluster(assets: assets)
        let after = PhotoCluster(assets: assets)

        #expect(before.id != after.id)
        #expect(before.contentKey == after.contentKey)
    }

    /// Review-state migration matches on a `Set` of identifiers, so view identity
    /// must ignore ordering too or the two disagree after a rescan.
    @Test func testContentKeyIgnoresAssetOrder() {
        let first = FakePhotoAsset(localIdentifier: "a")
        let second = FakePhotoAsset(localIdentifier: "b")

        #expect(PhotoCluster(assets: [first, second]).contentKey == PhotoCluster(assets: [second, first]).contentKey)
    }

    /// `ForEach` silently drops duplicate ids, which would make a cluster vanish.
    @Test func testDuplicateContentKeysGetDistinctIdentifiedClusterIDs() {
        let assets = [FakePhotoAsset(localIdentifier: "a"), FakePhotoAsset(localIdentifier: "b")]
        let arrangement = makeArrangement(
            clusters: [PhotoCluster(assets: assets), PhotoCluster(assets: assets)]
        )

        #expect(arrangement.remaining.count == 2)
        #expect(arrangement.remaining[0].id != arrangement.remaining[1].id)
    }

    // MARK: - Sorting

    @Test func testNewestSortOrdersByCreatedAtDescending() {
        let older = cluster(createdAt: Date(timeIntervalSince1970: 100))
        let newer = cluster(createdAt: Date(timeIntervalSince1970: 200))

        #expect(ids(makeArrangement(clusters: [older, newer], sort: .newest).remaining) == [newer.id, older.id])
    }

    @Test func testLargestClusterSortOrdersByAssetCountDescending() {
        let small = cluster(assetCount: 2)
        let large = cluster(assetCount: 5)

        #expect(ids(makeArrangement(clusters: [small, large], sort: .largestCluster).remaining) == [large.id, small.id])
    }

    @Test func testSimilaritySortOrdersByAverageSimilarityDescending() {
        let loose = cluster(similarity: 0.70)
        let tight = cluster(similarity: 0.95)

        #expect(ids(makeArrangement(clusters: [loose, tight], sort: .similarity).remaining) == [tight.id, loose.id])
    }

    /// `ClusterReviewStatus` is a `String` enum, so this sorts by the raw string
    /// ascending. Pinned verbatim to preserve the pre-refactor ordering.
    @Test func testReviewStatusSortOrdersByRawValueAscending() {
        let reviewed = cluster()
        let inReview = cluster()
        let statuses: [UUID: ClusterReviewStatus] = [
            reviewed.id: .reviewed,
            inReview.id: .inReview,
        ]

        let arrangement = makeArrangement(
            clusters: [reviewed, inReview],
            sort: .reviewStatus,
            statuses: statuses
        )

        #expect(ids(arrangement.remaining) == [inReview.id, reviewed.id])
    }

    @Test func testLargestCleanupOpportunitySortTreatsMissingSavingsAsZero() {
        let withSavings = cluster()
        let withoutSavings = cluster()

        let arrangement = makeArrangement(
            clusters: [withoutSavings, withSavings],
            sort: .largestCleanupOpportunity,
            savings: [withSavings.id: 5_000]
        )

        #expect(ids(arrangement.remaining) == [withSavings.id, withoutSavings.id])
    }

    // MARK: - Filtering

    @Test func testAdvancedFilterIsSkippedWithoutPremiumAccess() {
        var controls = CleanupClusterControls()
        controls.minimumClusterSize = .five
        let small = cluster(assetCount: 2)

        let locked = makeArrangement(
            clusters: [small],
            controls: controls,
            appliesAdvancedFilters: false
        )
        let unlocked = makeArrangement(
            clusters: [small],
            controls: controls,
            appliesAdvancedFilters: true
        )

        #expect(ids(locked.remaining) == [small.id])
        #expect(unlocked.remaining.isEmpty)
        #expect(unlocked.isEmptyAfterFiltering)
    }

    /// Documents the behaviour the arrangement freeze defers rather than changes:
    /// a reviewed cluster still leaves the `.needsReview` filter, just not while
    /// the details screen is open.
    @Test func testReviewedClusterIsDroppedUnderNeedsReviewFilter() {
        var controls = CleanupClusterControls()
        controls.reviewFilter = .needsReview
        let reviewed = cluster()

        let arrangement = makeArrangement(
            clusters: [reviewed],
            controls: controls,
            appliesAdvancedFilters: true,
            statuses: [reviewed.id: .reviewed]
        )

        #expect(arrangement.remaining.isEmpty)
        #expect(arrangement.hasAnyCluster)
        #expect(arrangement.isEmptyAfterFiltering)
    }

    // MARK: - Sectioning

    @Test func testNeedsReReviewClustersArePartitionedIntoNeedsReviewSection() {
        let resurfaced = cluster()
        let untouched = cluster()

        let arrangement = makeArrangement(
            clusters: [resurfaced, untouched],
            statuses: [resurfaced.id: .needsReReview, untouched.id: .inReview]
        )

        #expect(ids(arrangement.needsReview) == [resurfaced.id])
        #expect(ids(arrangement.remaining) == [untouched.id])
    }

    @Test func testEmptyClusterListIsNotReportedAsFilteredEmpty() {
        let arrangement = makeArrangement(clusters: [])

        #expect(!arrangement.hasAnyCluster)
        #expect(!arrangement.isEmptyAfterFiltering)
    }

    // MARK: - Freeze behaviour

    /// Proves the freeze is load-bearing: if the arrangement were re-derived on
    /// every review-state change, the grid would reorder underneath the user
    /// while `ClusterDetailsView` is still pushed.
    @Test func testReviewStatusChangeWouldReorderArrangement() {
        let first = cluster()
        let second = cluster()

        let before = makeArrangement(
            clusters: [first, second],
            sort: .reviewStatus,
            statuses: [first.id: .inReview, second.id: .reviewed]
        )
        let after = makeArrangement(
            clusters: [first, second],
            sort: .reviewStatus,
            statuses: [first.id: .reviewed, second.id: .inReview]
        )

        #expect(ids(before.remaining) == [first.id, second.id])
        #expect(ids(after.remaining) == [second.id, first.id])
        #expect(before != after)
    }

    /// Re-deriving on regenerated cluster ids keeps view identity stable while
    /// refreshing the `PhotoCluster` values the cards use for status lookups.
    @Test func testArrangementIsRederivedWhenClusterIDsChange() {
        let assets = [FakePhotoAsset(localIdentifier: "a"), FakePhotoAsset(localIdentifier: "b")]
        let before = PhotoCluster(assets: assets)
        let after = PhotoCluster(assets: assets)

        let beforeArrangement = makeArrangement(clusters: [before])
        let afterArrangement = makeArrangement(clusters: [after])

        #expect(beforeArrangement.remaining.map(\.id) == afterArrangement.remaining.map(\.id))
        #expect(ids(afterArrangement.remaining) == [after.id])
    }

    // MARK: - Scroll anchor survival

    @Test func testAnchorIsKeptWhenItSurvivesTheRefresh() {
        let first = cluster()
        let second = cluster()
        let before = makeArrangement(clusters: [first, second])
        let after = makeArrangement(clusters: [first, second])
        let anchor = before.orderedIDs[1]

        #expect(after.preservedAnchor(anchor, replacing: before) == anchor)
    }

    /// Reconciliation changes the contents of the cluster the user deleted from,
    /// so its row id changes. Without a fallback the anchor is lost and the grid
    /// slides once the rescan lands.
    @Test func testAnchorFallsBackToTheRowBelowWhenItDisappears() {
        let survivingAbove = cluster()
        let deleted = cluster()
        let survivingBelow = cluster()

        let before = makeArrangement(clusters: [survivingAbove, deleted, survivingBelow])
        let after = makeArrangement(clusters: [survivingAbove, survivingBelow])
        let anchor = before.orderedIDs[1]

        #expect(after.preservedAnchor(anchor, replacing: before) == after.orderedIDs[1])
    }

    @Test func testAnchorFallsBackUpwardWhenNothingSurvivesBelow() {
        let survivingAbove = cluster()
        let deleted = cluster()

        let before = makeArrangement(clusters: [survivingAbove, deleted])
        let after = makeArrangement(clusters: [survivingAbove])
        let anchor = before.orderedIDs[1]

        #expect(after.preservedAnchor(anchor, replacing: before) == after.orderedIDs[0])
    }

    /// A cluster promoted to "Needs review" by reconciliation moves to the top
    /// section. The anchor has to follow the row, not its position.
    @Test func testAnchorFollowsAClusterAcrossSectionMigration() {
        let promoted = cluster()
        let untouched = cluster()

        let before = makeArrangement(clusters: [promoted, untouched])
        let after = makeArrangement(
            clusters: [promoted, untouched],
            statuses: [promoted.id: .needsReReview]
        )
        let anchor = before.remaining[0].id

        #expect(after.needsReview.map(\.id) == [anchor])
        #expect(after.preservedAnchor(anchor, replacing: before) == anchor)
    }

    @Test func testAnchorIsClearedWhenEveryRowDisappears() {
        let only = cluster()
        let before = makeArrangement(clusters: [only])
        let after = makeArrangement(clusters: [])

        #expect(after.preservedAnchor(before.orderedIDs[0], replacing: before) == nil)
    }

    @Test func testNilAnchorStaysNil() {
        let before = makeArrangement(clusters: [cluster()])
        let after = makeArrangement(clusters: [cluster()])

        #expect(after.preservedAnchor(nil, replacing: before) == nil)
    }

    // MARK: - Helpers

    private func makeArrangement(
        clusters: [PhotoCluster],
        controls: CleanupClusterControls = CleanupClusterControls(),
        sort: CleanupClusterSort? = nil,
        appliesAdvancedFilters: Bool = true,
        statuses: [UUID: ClusterReviewStatus] = [:],
        savings: [UUID: Int64] = [:]
    ) -> CleanupClusterArrangement {
        var controls = controls
        if let sort { controls.sort = sort }

        return .make(
            clusters: clusters,
            controls: controls,
            appliesAdvancedFilters: appliesAdvancedFilters,
            reviewStatus: { statuses[$0] ?? .notReviewed },
            estimatedSavings: { savings[$0] ?? 0 }
        )
    }

    private func cluster(
        assetCount: Int = 2,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        similarity: Float = 0.8
    ) -> PhotoCluster {
        PhotoCluster(
            assets: (0..<assetCount).map { _ in FakePhotoAsset() },
            createdAt: createdAt,
            averageSimilarity: similarity
        )
    }

    private func ids(_ clusters: [IdentifiedCluster]) -> [UUID] {
        clusters.map(\.cluster.id)
    }
}
