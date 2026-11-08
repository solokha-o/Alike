import Core
import DesignSystem
import SwiftUI
import Foundation
import Testing
@testable import Details

/// A tile has three states and the Best Shot wins over the selection. VoiceOver
/// must say the same thing the tile shows, so the precedence is pinned here.
struct PhotoTilePresentationTests {
    private func presentation(
        isBestShot: Bool = false,
        isSelected: Bool = false,
        confidence: BestShotConfidence = .automatic
    ) -> PhotoTilePresentation {
        PhotoTilePresentation(isBestShot: isBestShot, isSelected: isSelected, bestShotConfidence: confidence)
    }

    // MARK: - Accessibility

    @Test func testUnselectedTileReadsAsNotSelected() {
        let tile = presentation()
        #expect(tile.accessibilityLabel == DetailsL10n.ClusterDetails.notSelected)
        #expect(tile.accessibilityValue == DetailsL10n.ClusterDetails.notSelected)
        #expect(tile.accessibilityHint == DetailsL10n.ClusterDetails.doubleTapSelectThisPhoto)
    }

    @Test func testSelectedTileReadsAsSelected() {
        let tile = presentation(isSelected: true)
        #expect(tile.accessibilityLabel == DetailsL10n.ClusterDetails.selectedForCleanupReview)
        #expect(tile.accessibilityValue == DetailsL10n.ClusterDetails.selected)
        #expect(tile.accessibilityHint == DetailsL10n.ClusterDetails.doubleTapRemoveThisPhoto)
    }

    @Test func testBestShotWinsOverSelectionInEveryAccessibilityText() {
        for tile in [presentation(isBestShot: true), presentation(isBestShot: true, isSelected: true)] {
            #expect(tile.accessibilityLabel == DetailsL10n.Common.bestShot)
            #expect(tile.accessibilityValue == DetailsL10n.Common.bestShot)
            #expect(tile.accessibilityHint == DetailsL10n.ClusterDetails.thisPhotoKeptAsBest)
        }
    }

    @Test func testLowConfidenceBestShotSaysProbably() {
        let tile = presentation(isBestShot: true, confidence: .lowConfidence)
        #expect(tile.accessibilityLabel == DetailsL10n.ClusterDetails.probablyBestShot)
        #expect(tile.accessibilityValue == DetailsL10n.ClusterDetails.probablyBestShot)
    }

    /// Without a Best Shot a double tap selects nothing, so VoiceOver must not
    /// offer it.
    @Test func testTileThatCannotBeSelectedSaysToChooseABestShotFirst() {
        let tile = PhotoTilePresentation(
            isBestShot: false,
            isSelected: false,
            bestShotConfidence: .unresolved,
            canSelect: false
        )
        #expect(tile.accessibilityHint == DetailsL10n.ClusterDetails.chooseBestShotBeforeSelecting)
        #expect(tile.accessibilityLabel == DetailsL10n.ClusterDetails.notSelected)
    }

    // MARK: - Border

    @Test func testBorderFollowsTheSamePrecedence() {
        #expect(presentation().borderColor == .clear)
        #expect(presentation().borderLineWidth == 0)

        #expect(presentation(isSelected: true).borderColor == .accent)
        #expect(presentation(isSelected: true).borderLineWidth == 2)

        let gold = Color.heroGold.opacity(0.9)
        #expect(presentation(isBestShot: true).borderColor == gold)
        #expect(presentation(isBestShot: true, isSelected: true).borderColor == gold)
        #expect(presentation(isBestShot: true).borderLineWidth == 2)
    }

    // MARK: - Thumbnail loading

    @Test func testSquareTileRequestsTheLargerThumbnail() {
        #expect(PhotoTilePresentation.thumbnailTargetSize(aspectRatio: 1) == CGSize(width: 1_000, height: 1_000))
        #expect(PhotoTilePresentation.thumbnailTargetSize(aspectRatio: 0.75) == CGSize(width: 300, height: 300))
    }

    @Test func testImageLoadTaskIDFormat() {
        #expect(PhotoTilePresentation.imageLoadTaskID(
            localIdentifier: "a",
            modificationDate: Date(timeIntervalSinceReferenceDate: 5),
            attempt: 2
        ) == "a#5.0#2")
        #expect(PhotoTilePresentation.imageLoadTaskID(localIdentifier: "a", modificationDate: nil, attempt: 0) == "a#0.0#0")
    }

    /// After Apply or Revert the tile must reload, and a retry must reload too.
    @Test func testImageLoadTaskIDChangesWithEditAndRetry() {
        let date = Date(timeIntervalSinceReferenceDate: 5)
        let base = PhotoTilePresentation.imageLoadTaskID(localIdentifier: "a", modificationDate: date, attempt: 0)

        #expect(base != PhotoTilePresentation.imageLoadTaskID(
            localIdentifier: "a",
            modificationDate: date.addingTimeInterval(1),
            attempt: 0
        ))
        #expect(base != PhotoTilePresentation.imageLoadTaskID(localIdentifier: "a", modificationDate: date, attempt: 1))
    }
}
