import XCTest
import Core
@testable import Cleanup

final class ClusterReviewStateResurfacerTests: XCTestCase {
    private let previousClusterID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let newClusterID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!

    /// A best shot the user picked has to outlive a rescan whose recomputed pick
    /// differs, otherwise their choice silently reverts to the heuristic's.
    func testUserSelectedBestShotSurvivesRecomputedChange() {
        let previous = snapshot(id: previousClusterID, favoriteIdentifier: "a")
        let new = snapshot(id: newClusterID, favoriteIdentifier: "b")
        let existing = reviewState(
            clusterID: previousClusterID,
            bestShotLocalIdentifier: "a",
            isBestShotUserSelected: true
        )

        let result = ClusterReviewStateResurfacer.resurface(
            previousSnapshots: [previous],
            newSnapshots: [new],
            existingReviewStates: [previousClusterID: existing]
        )

        XCTAssertEqual(result.resurfacingStates[newClusterID], .unchanged)
        XCTAssertEqual(result.migratedReviewStates[newClusterID]?.bestShotLocalIdentifier, "a")
        XCTAssertEqual(result.migratedReviewStates[newClusterID]?.isBestShotUserSelected, true)
        XCTAssertEqual(result.migratedReviewStates[newClusterID]?.status, .reviewed)
        XCTAssertEqual(result.migratedReviewStates[newClusterID]?.selectedLocalIdentifiers, ["b"])
    }

    func testRecomputedBestShotChangeWithoutOverrideStillResurfaces() {
        let previous = snapshot(id: previousClusterID, favoriteIdentifier: "a")
        let new = snapshot(id: newClusterID, favoriteIdentifier: "b")
        let existing = reviewState(
            clusterID: previousClusterID,
            bestShotLocalIdentifier: "a",
            isBestShotUserSelected: false
        )

        let result = ClusterReviewStateResurfacer.resurface(
            previousSnapshots: [previous],
            newSnapshots: [new],
            existingReviewStates: [previousClusterID: existing]
        )

        XCTAssertEqual(result.resurfacingStates[newClusterID], .changed)
        XCTAssertEqual(result.migratedReviewStates[newClusterID]?.status, .needsReReview)
        XCTAssertEqual(result.migratedReviewStates[newClusterID]?.bestShotLocalIdentifier, "b")
        XCTAssertEqual(result.migratedReviewStates[newClusterID]?.isBestShotUserSelected, false)
    }

    func testOverrideDoesNotSurviveChangedAssetSet() {
        let previous = snapshot(id: previousClusterID, favoriteIdentifier: "a")
        let new = PhotoClusterSnapshot(
            id: newClusterID,
            createdAt: Date(timeIntervalSince1970: 0),
            averageSimilarity: 0.9,
            assets: [asset(id: "a", isFavorite: true), asset(id: "c", isFavorite: false)]
        )
        let existing = reviewState(
            clusterID: previousClusterID,
            bestShotLocalIdentifier: "a",
            isBestShotUserSelected: true
        )

        let result = ClusterReviewStateResurfacer.resurface(
            previousSnapshots: [previous],
            newSnapshots: [new],
            existingReviewStates: [previousClusterID: existing]
        )

        XCTAssertEqual(result.resurfacingStates[newClusterID], .changed)
        XCTAssertEqual(result.migratedReviewStates[newClusterID]?.status, .needsReReview)
        XCTAssertEqual(result.migratedReviewStates[newClusterID]?.isBestShotUserSelected, false)
        XCTAssertTrue(result.migratedReviewStates[newClusterID]?.selectedLocalIdentifiers.isEmpty ?? false)
    }

    // MARK: - Helpers

    /// Two identically sized assets where only the favorite flag decides the
    /// computed best shot, so tests can move that pick without touching the set.
    private func snapshot(id: UUID, favoriteIdentifier: String) -> PhotoClusterSnapshot {
        PhotoClusterSnapshot(
            id: id,
            createdAt: Date(timeIntervalSince1970: 0),
            averageSimilarity: 0.9,
            assets: [
                asset(id: "a", isFavorite: favoriteIdentifier == "a"),
                asset(id: "b", isFavorite: favoriteIdentifier == "b")
            ]
        )
    }

    private func asset(id: String, isFavorite: Bool) -> PhotoClusterAssetSnapshot {
        PhotoClusterAssetSnapshot(
            localIdentifier: id,
            creationDate: Date(timeIntervalSince1970: 100),
            modificationDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            isFavorite: isFavorite
        )
    }

    private func reviewState(
        clusterID: UUID,
        bestShotLocalIdentifier: String,
        isBestShotUserSelected: Bool
    ) -> ClusterReviewState {
        ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: bestShotLocalIdentifier,
            isBestShotUserSelected: isBestShotUserSelected,
            selectedLocalIdentifiers: ["b"],
            mode: .selection,
            status: .reviewed,
            estimatedSavingsBytes: 500,
            updatedAt: Date(timeIntervalSince1970: 50)
        )
    }
}
