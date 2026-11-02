import Core
import DesignSystem
import Foundation
import SwiftUI

/// What a photo tile says and draws for its selection state. Kept apart from
/// the view so the wording and the state precedence can be tested without
/// hosting it: the Best Shot wins over the selection everywhere.
struct PhotoTilePresentation {
    let isBestShot: Bool
    let isSelected: Bool
    let bestShotConfidence: BestShotConfidence

    var borderColor: Color {
        if isBestShot {
            return .heroGold.opacity(0.9)
        }
        if isSelected {
            return .accent
        }
        return .clear
    }

    var borderLineWidth: CGFloat {
        (isBestShot || isSelected) ? 2 : 0
    }

    var accessibilityLabel: String {
        if isBestShot {
            return bestShotConfidence.badgeTitle
        }
        if isSelected {
            return DetailsL10n.ClusterDetails.selectedForCleanupReview
        }
        return DetailsL10n.ClusterDetails.notSelected
    }

    var accessibilityValue: String {
        if isBestShot {
            return bestShotConfidence.badgeTitle
        }
        return isSelected ? DetailsL10n.ClusterDetails.selected : DetailsL10n.ClusterDetails.notSelected
    }

    var accessibilityHint: String {
        if isBestShot {
            return DetailsL10n.ClusterDetails.thisPhotoKeptAsBest
        }
        return isSelected
            ? DetailsL10n.ClusterDetails.doubleTapRemoveThisPhoto
            : DetailsL10n.ClusterDetails.doubleTapSelectThisPhoto
    }

    static func thumbnailTargetSize(aspectRatio: CGFloat) -> CGSize {
        aspectRatio == 1
            ? CGSize(width: 1_000, height: 1_000)
            : CGSize(width: 300, height: 300)
    }

    /// The modification date is part of the key because it is part of the
    /// thumbnail cache key: after Apply or Revert the view model hands over a
    /// re-read asset, and only a changed key re-runs the load instead of
    /// leaving the pre-edit picture on the tile.
    static func imageLoadTaskID(localIdentifier: String, modificationDate: Date?, attempt: Int) -> String {
        "\(localIdentifier)#\(modificationDate?.timeIntervalSinceReferenceDate ?? 0)#\(attempt)"
    }
}
