import Core
import DesignSystem
import SwiftUI
import XCTest
@testable import Details

/// A tile has three states and the Best Shot wins over the selection. VoiceOver
/// must say the same thing the tile shows, so the precedence is pinned here.
final class PhotoTilePresentationTests: XCTestCase {
    private func presentation(
        isBestShot: Bool = false,
        isSelected: Bool = false,
        confidence: BestShotConfidence = .automatic
    ) -> PhotoTilePresentation {
        PhotoTilePresentation(isBestShot: isBestShot, isSelected: isSelected, bestShotConfidence: confidence)
    }

    // MARK: - Accessibility

    func testUnselectedTileReadsAsNotSelected() {
        let tile = presentation()
        XCTAssertEqual(tile.accessibilityLabel, DetailsL10n.ClusterDetails.notSelected)
        XCTAssertEqual(tile.accessibilityValue, DetailsL10n.ClusterDetails.notSelected)
        XCTAssertEqual(tile.accessibilityHint, DetailsL10n.ClusterDetails.doubleTapSelectThisPhoto)
    }

    func testSelectedTileReadsAsSelected() {
        let tile = presentation(isSelected: true)
        XCTAssertEqual(tile.accessibilityLabel, DetailsL10n.ClusterDetails.selectedForCleanupReview)
        XCTAssertEqual(tile.accessibilityValue, DetailsL10n.ClusterDetails.selected)
        XCTAssertEqual(tile.accessibilityHint, DetailsL10n.ClusterDetails.doubleTapRemoveThisPhoto)
    }

    func testBestShotWinsOverSelectionInEveryAccessibilityText() {
        for tile in [presentation(isBestShot: true), presentation(isBestShot: true, isSelected: true)] {
            XCTAssertEqual(tile.accessibilityLabel, DetailsL10n.Common.bestShot)
            XCTAssertEqual(tile.accessibilityValue, DetailsL10n.Common.bestShot)
            XCTAssertEqual(tile.accessibilityHint, DetailsL10n.ClusterDetails.thisPhotoKeptAsBest)
        }
    }

    func testLowConfidenceBestShotSaysProbably() {
        let tile = presentation(isBestShot: true, confidence: .lowConfidence)
        XCTAssertEqual(tile.accessibilityLabel, DetailsL10n.ClusterDetails.probablyBestShot)
        XCTAssertEqual(tile.accessibilityValue, DetailsL10n.ClusterDetails.probablyBestShot)
    }

    /// Without a Best Shot a double tap selects nothing, so VoiceOver must not
    /// offer it.
    func testTileThatCannotBeSelectedSaysToChooseABestShotFirst() {
        let tile = PhotoTilePresentation(
            isBestShot: false,
            isSelected: false,
            bestShotConfidence: .unresolved,
            canSelect: false
        )
        XCTAssertEqual(tile.accessibilityHint, DetailsL10n.ClusterDetails.chooseBestShotBeforeSelecting)
        XCTAssertEqual(tile.accessibilityLabel, DetailsL10n.ClusterDetails.notSelected)
    }

    // MARK: - Border

    func testBorderFollowsTheSamePrecedence() {
        XCTAssertEqual(presentation().borderColor, .clear)
        XCTAssertEqual(presentation().borderLineWidth, 0)

        XCTAssertEqual(presentation(isSelected: true).borderColor, .accent)
        XCTAssertEqual(presentation(isSelected: true).borderLineWidth, 2)

        let gold = Color.heroGold.opacity(0.9)
        XCTAssertEqual(presentation(isBestShot: true).borderColor, gold)
        XCTAssertEqual(presentation(isBestShot: true, isSelected: true).borderColor, gold)
        XCTAssertEqual(presentation(isBestShot: true).borderLineWidth, 2)
    }

    // MARK: - Thumbnail loading

    func testSquareTileRequestsTheLargerThumbnail() {
        XCTAssertEqual(
            PhotoTilePresentation.thumbnailTargetSize(aspectRatio: 1),
            CGSize(width: 1_000, height: 1_000)
        )
        XCTAssertEqual(
            PhotoTilePresentation.thumbnailTargetSize(aspectRatio: 0.75),
            CGSize(width: 300, height: 300)
        )
    }

    func testImageLoadTaskIDFormat() {
        XCTAssertEqual(
            PhotoTilePresentation.imageLoadTaskID(
                localIdentifier: "a",
                modificationDate: Date(timeIntervalSinceReferenceDate: 5),
                attempt: 2
            ),
            "a#5.0#2"
        )
        XCTAssertEqual(
            PhotoTilePresentation.imageLoadTaskID(localIdentifier: "a", modificationDate: nil, attempt: 0),
            "a#0.0#0"
        )
    }

    /// After Apply or Revert the tile must reload, and a retry must reload too.
    func testImageLoadTaskIDChangesWithEditAndRetry() {
        let date = Date(timeIntervalSinceReferenceDate: 5)
        let base = PhotoTilePresentation.imageLoadTaskID(localIdentifier: "a", modificationDate: date, attempt: 0)

        XCTAssertNotEqual(
            base,
            PhotoTilePresentation.imageLoadTaskID(
                localIdentifier: "a",
                modificationDate: date.addingTimeInterval(1),
                attempt: 0
            )
        )
        XCTAssertNotEqual(
            base,
            PhotoTilePresentation.imageLoadTaskID(localIdentifier: "a", modificationDate: date, attempt: 1)
        )
    }
}
