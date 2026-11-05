import Foundation
import Photos
import SwiftUI
import DesignSystem
import Storage

extension ClusterDetailsViewModel {
    func isBestShot(_ localIdentifier: String) -> Bool {
        bestShotAssetID == localIdentifier
    }

    /// Whether the Best Shot marking should be visible yet. While the measured
    /// ranking is still landing the badge stays hidden, so it never appears on
    /// one photo and then hops to another.
    var isBestShotVisible: Bool {
        !bestShotAssetID.isEmpty && !isRankingQualityPending
    }

    func isSelected(_ localIdentifier: String) -> Bool {
        selectedAssetIDs.contains(localIdentifier)
    }

}
