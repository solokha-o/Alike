import Foundation
import Photos
import SwiftUI
import DesignSystem
import Storage

extension ClusterDetailsViewModel {
    func handleDeleteError(_ error: PhotoCleanupError) {
        let eventID = AlikeEventID.cleanup(cleanupSelectionID)
        if error == .notAuthorized {
            publishAlikeEvent(.permissionBlocked(
                id: eventID,
                context: AlikePermissionContext(operation: .cleanup)
            ))
        } else {
            publishAlikeEvent(.recoverableFailure(
                id: eventID,
                context: AlikeErrorContext(operation: .cleanup)
            ))
        }

        switch error {
        case .nothingSelected:
            applyActionFailure(
                message: DetailsL10n.Common.selectAtLeastOnePhoto,
                offersOpenSettings: false
            )
        case .notAuthorized:
            applyActionFailure(
                message: DetailsL10n.Common.alikeNeedsPhotoLibraryAccess,
                offersOpenSettings: true
            )
        case .selectedAssetsUnavailable:
            applyActionFailure(
                message: DetailsL10n.Common.someSelectedPhotosNoLonger,
                offersOpenSettings: true
            )
        case .deleteFailed:
            applyActionFailure(
                message: DetailsL10n.Common.couldntMoveSelectedPhotosPlease,
                offersOpenSettings: false
            )
        }
    }

    func applyActionFailure(
        message: String,
        offersOpenSettings: Bool,
        title: String = DetailsL10n.Common.cleanupUnavailable
    ) {
        actionErrorMessage = message
        actionErrorTitle = title
        shouldOfferOpenSettings = offersOpenSettings
        pendingCompletionRecord = nil
    }

    func applyState(
        bestShotAssetID: String,
        isBestShotUserSelected: Bool,
        selectedAssetIDs: Set<String>,
        isReviewConfirmed: Bool,
        reviewMode _: ClusterReviewMode,
        persistedStatus: ClusterReviewStatus?
    ) {
        self.bestShotAssetID = bestShotAssetID
        self.bestShotLabel = Self.bestShotLabel(
            for: bestShotAssetID,
            in: assetSnapshots
        )
        self.isBestShotUserSelected = isBestShotUserSelected
        self.selectedAssetIDs = selectedAssetIDs
        self.isReviewConfirmed = isReviewConfirmed
        self.reviewMode = .selection
        refreshDerivedState()
        // A rescan that changed the cluster outranks the stored confirmation:
        // the user has not seen this set of photos yet.
        if persistedStatus == .needsReReview {
            self.isReviewConfirmed = false
            reviewStatus = .needsReReview
            estimatedSavingsBytes = 0
        }
    }

    func refreshDerivedState(emitsReviewCompletion: Bool = false) {
        let previousStatus = reviewStatus
        estimatedSavingsBytes = assetSnapshots
            .filter { selectedAssetIDs.contains($0.localIdentifier) }
            .reduce(into: Int64(0)) { partialResult, snapshot in
                partialResult += snapshot.estimatedCleanupBytes
            }
        reviewStatus = Self.reviewStatus(
            isReviewConfirmed: isReviewConfirmed,
            selectedAssetIDs: selectedAssetIDs,
            assetCount: assetSnapshots.count,
            bestShotAssetID: bestShotAssetID,
            isBestShotUnresolved: bestShotConfidence == .unresolved
        )

        if emitsReviewCompletion, previousStatus != .reviewed, reviewStatus == .reviewed {
            reviewCompletionGeneration &+= 1
            successFeedbackTrigger &+= 1
            bestShotCelebrationCue = AlikeReviewReactionCue(
                id: .init(clusterID: cluster.id, generation: reviewCompletionGeneration)
            )
        } else if reviewStatus != .reviewed {
            bestShotCelebrationCue = nil
        }

        publishCleanupSelectionReaction()
    }

    func publishCleanupSelectionReaction() {
        if selectedAssetIDs.isEmpty {
            publishAlikeEvent(.cleanupSelectionCleared(id: cleanupSelectionID))
        } else {
            publishAlikeEvent(.cleanupReady(
                id: cleanupSelectionID,
                summary: AlikeCleanupSummary(
                    itemCount: selectedAssetIDs.count,
                    estimatedSavingsBytes: estimatedSavingsBytes
                )
            ))
        }
    }

    func publishAlikeEvent(_ event: AlikeEvent) {
        _ = alikeReactionResolver.apply(event)
        currentAlikeReaction = alikeReactionResolver.currentCue
    }
}
