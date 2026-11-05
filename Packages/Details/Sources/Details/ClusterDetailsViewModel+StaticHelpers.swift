import Foundation
import Photos
import SwiftUI
import DesignSystem
import Storage

extension ClusterDetailsViewModel {
    /// A cluster is reviewed once the user says so, not once only one photo is
    /// left: keeping two of five is as final a decision as keeping one.
    static func reviewStatus(
        isReviewConfirmed: Bool,
        selectedAssetIDs: Set<String>,
        assetCount: Int,
        bestShotAssetID: String,
        isBestShotUnresolved: Bool = false
    ) -> ClusterReviewStatus {
        guard assetCount > 0 else { return .notReviewed }
        guard !bestShotAssetID.isEmpty || isBestShotUnresolved else { return .notReviewed }
        guard !isReviewConfirmed else { return .reviewed }
        return selectedAssetIDs.isEmpty ? .notReviewed : .inReview
    }
}

private extension ClusterDetailsViewModel {
    static func bestShotLocalIdentifier(from snapshots: [ReviewAssetSnapshot]) -> String? {
        PhotoClusterBestShot.bestShotLocalIdentifier(from: snapshots.map(\.photoClusterAssetSnapshot))
    }
}

extension ClusterDetailsViewModel {
    static func bestShotLabel(
        for localIdentifier: String,
        in snapshots: [ReviewAssetSnapshot]
    ) -> String {
        guard
            let creationDate = snapshots.first(where: { $0.localIdentifier == localIdentifier })?.creationDate
        else {
            return DetailsL10n.Common.bestShot
        }
        return creationDate.alikeFormatted(date: .abbreviated, time: .shortened)
    }

    nonisolated static func prepareAssetSnapshots(
        for cluster: PhotoCluster
    ) async throws -> [ReviewAssetSnapshot] {
        let preparationTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try cluster.assets.map { asset in
                try Task.checkCancellation()
                return ReviewAssetSnapshot(asset: asset)
            }
        }

        return try await withTaskCancellationHandler {
            try await preparationTask.value
        } onCancel: {
            preparationTask.cancel()
        }
    }
}
