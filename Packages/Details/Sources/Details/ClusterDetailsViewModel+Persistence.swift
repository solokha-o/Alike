import Foundation
import Photos
import SwiftUI
import DesignSystem
import Storage

extension ClusterDetailsViewModel {
    @discardableResult
    func enqueueCurrentStatePersistence() -> Task<Void, Never>? {
        // An unresolved cluster still has review progress worth keeping; it
        // stores an empty best shot, which loads back as "not chosen yet".
        guard !bestShotAssetID.isEmpty || bestShotConfidence == .unresolved else { return nil }
        let state = ClusterReviewState(
            clusterID: cluster.id,
            bestShotLocalIdentifier: bestShotAssetID,
            isBestShotUserSelected: isBestShotUserSelected,
            selectedLocalIdentifiers: selectedAssetIDs,
            isReviewConfirmed: isReviewConfirmed,
            mode: reviewMode,
            status: reviewStatus,
            estimatedSavingsBytes: estimatedSavingsBytes,
            resurfacingState: reviewStatus == .needsReReview ? .changed : nil
        )
        let previousTask = persistenceTask
        let reviewRepository = reviewRepository

        let task = Task { [weak self] in
            await previousTask?.value
            do {
                try await reviewRepository.saveReviewState(state)
            } catch {
                AppLog.storage.error("\(AppLog.tag(.error, "Failed to save review state: \(error.localizedDescription)"))")
            }
            self?.persistedRevision &+= 1
        }
        persistenceTask = task
        return task
    }
}
