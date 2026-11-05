import Foundation
import Photos
import SwiftUI
import DesignSystem
import Storage

// MARK: - Reversible auto-enhancement

extension ClusterDetailsViewModel {
    /// Hidden entirely when no service is injected or the asset cannot be
    /// edited, so the UI never offers an action that would fail.
    var isEnhancementActionVisible: Bool {
        enhancementService != nil
            && !bestShotAssetID.isEmpty
            && enhancementState != .unavailable
    }

    /// The live asset behind the current Best Shot, for previews and edits.
    var bestShotAsset: PHAsset? {
        assets.first { $0.localIdentifier == bestShotAssetID }
    }

    /// The live asset an enhancement request was frozen on.
    func asset(withIdentifier localIdentifier: String) -> PHAsset? {
        assets.first { $0.localIdentifier == localIdentifier }
    }

    /// Re-reads one asset after Alike wrote to it, so the grid stops showing
    /// the pre-edit picture. Thumbnails are cached under the asset's
    /// `modificationDate`; without a fresh snapshot the cache answers with the
    /// image the user was looking at before Apply or Revert.
    func refreshAsset(withIdentifier localIdentifier: String) {
        guard !localIdentifier.isEmpty, let refreshed = assetRefresher(localIdentifier) else { return }
        refreshedAssets[localIdentifier] = refreshed
    }

    var isBestShotEnhanced: Bool {
        isEnhanced(bestShotAssetID)
    }

    func isEnhanced(_ localIdentifier: String) -> Bool {
        !localIdentifier.isEmpty && enhancedAssetIDs.contains(localIdentifier)
    }

    /// Re-reads what the library says about the current Best Shot — whether it
    /// can be edited and whether it already carries Alike's edit — in a single
    /// question, because resolving a photo for editing is expensive.
    func refreshEnhancementAvailability() async {
        guard let enhancementService, !bestShotAssetID.isEmpty else {
            enhancementState = .unavailable
            enhancementPreview = nil
            isBestShotEditedElsewhere = false
            return
        }

        let localIdentifier = bestShotAssetID
        let availability = await enhancementService.availability(localIdentifier: localIdentifier)
        guard localIdentifier == bestShotAssetID else { return }

        isBestShotEditedElsewhere = availability == .editedElsewhere
        switch availability {
        case .unavailable:
            enhancementState = .unavailable
        case .available, .editedElsewhere:
            enhancedAssetIDs.remove(localIdentifier)
            enhancementState = .idle
        case .enhanced:
            enhancedAssetIDs.insert(localIdentifier)
            enhancementState = .applied
        }
        enhancementPreview = nil
    }

    /// Renders the "after" image. Nothing is written to the library yet.
    /// Claims the current Best Shot for an enhancement the user just asked for.
    ///
    /// Called when the action is tapped rather than when the preview task
    /// starts: between those two moments a late ranking could otherwise move
    /// the Best Shot, and the cover would open on a different photo than the
    /// one the user tapped. Returns the frozen identifier, or `nil` when there
    /// is nothing to enhance.
    func beginEnhancementRequest() -> String? {
        guard enhancementService != nil, !bestShotAssetID.isEmpty else { return nil }
        guard enhancementState != .unavailable else { return nil }
        interactionGeneration &+= 1
        return bestShotAssetID
    }

    /// `requestedIdentifier` is required on purpose: the caller must say which
    /// photo the user asked to enhance, so no presentation path can silently
    /// fall back to whatever the Best Shot happens to be by now.
    func enhance(previewSize: CGSize, for requestedIdentifier: String) async {
        guard let enhancementService, !bestShotAssetID.isEmpty else { return }
        guard enhancementState == .idle || enhancementState == .previewing else { return }

        // The photo the user tapped is the photo this preview is for.
        let localIdentifier = requestedIdentifier
        guard localIdentifier == bestShotAssetID else { return }
        interactionGeneration &+= 1
        // Cancelling while the original is still coming down from iCloud bumps
        // this, so the render that lands afterwards cannot re-open a preview
        // the user already dismissed — or leave the action stuck busy.
        let generation = interactionGeneration
        enhancementState = .preparingPreview
        do {
            let preview = try await enhancementService.renderPreview(
                localIdentifier: localIdentifier,
                targetSize: previewSize
            )
            guard localIdentifier == bestShotAssetID, generation == interactionGeneration else { return }
            enhancementPreview = preview
            enhancementState = .previewing
        } catch {
            guard localIdentifier == bestShotAssetID, generation == interactionGeneration else { return }
            handleEnhancementError(error, fallbackState: .idle)
        }
    }

    /// Cancelling is offered while the preview is still being prepared, so it
    /// has to end that wait too: leaving `.preparingPreview` behind keeps the
    /// enhance action disabled for as long as the screen is open.
    func dismissEnhancementPreview() {
        guard enhancementState == .previewing || enhancementState == .preparingPreview else { return }
        interactionGeneration &+= 1
        enhancementPreview = nil
        enhancementState = .idle
    }

    func applyEnhancement(for requestedIdentifier: String) async {
        guard let enhancementService, !bestShotAssetID.isEmpty else { return }
        guard enhancementState == .idle || enhancementState == .previewing else { return }

        let localIdentifier = requestedIdentifier
        guard localIdentifier == bestShotAssetID else { return }
        interactionGeneration &+= 1
        let previousState = enhancementState
        enhancementState = .applying
        do {
            _ = try await enhancementService.applyEnhancement(
                localIdentifier: localIdentifier,
                // The preview screen stated what this replaces before the user
                // reached this button.
                replacingOtherEdits: isBestShotEditedElsewhere
            )
            // The badge belongs to the photo that was edited, whatever is the
            // Best Shot by now; the shared state only speaks for the photo
            // currently on the tile.
            enhancedAssetIDs.insert(localIdentifier)
            refreshAsset(withIdentifier: localIdentifier)
            guard localIdentifier == bestShotAssetID else {
                await refreshEnhancementAvailability()
                return
            }
            isBestShotEditedElsewhere = false
            enhancementPreview = nil
            enhancementState = .applied
        } catch {
            // A failed edit leaves the photo, the selection and the review
            // exactly as they were; only the enhancement state moves.
            guard localIdentifier == bestShotAssetID else { return }
            handleEnhancementError(error, fallbackState: previousState)
        }
    }

    func revertEnhancement() async {
        guard let enhancementService, !bestShotAssetID.isEmpty else { return }
        guard enhancementState == .applied else { return }

        interactionGeneration &+= 1

        let localIdentifier = bestShotAssetID
        enhancementState = .reverting
        do {
            try await enhancementService.revertToOriginal(localIdentifier: localIdentifier)
            enhancedAssetIDs.remove(localIdentifier)
            refreshAsset(withIdentifier: localIdentifier)
            guard localIdentifier == bestShotAssetID else {
                await refreshEnhancementAvailability()
                return
            }
            enhancementPreview = nil
            enhancementState = .idle
        } catch {
            guard localIdentifier == bestShotAssetID else { return }
            handleEnhancementError(error, fallbackState: .applied)
        }
    }

    func handleEnhancementError(_ error: Error, fallbackState: PhotoEnhancementState) {
        let enhancementError = (error as? PhotoEnhancementError) ?? .saveFailed
        enhancementPreview = nil
        enhancementState = .failed(enhancementError)
        enhancementRecoveryState = fallbackState
        publishAlikeEvent(.recoverableFailure(
            id: AlikeEventID.cleanup(cleanupSelectionID),
            context: AlikeErrorContext(operation: .enhancement)
        ))
        applyActionFailure(
            message: Self.enhancementErrorMessage(for: enhancementError),
            offersOpenSettings: enhancementError == .notAuthorized
                || enhancementError == .limitedAccessNotEditable,
            title: DetailsL10n.ClusterDetails.enhancementUnavailableTitle
        )
    }

    static func enhancementErrorMessage(for error: PhotoEnhancementError) -> String {
        switch error {
        case .notAuthorized:
            return DetailsL10n.Common.alikeNeedsPhotoLibraryAccess
        case .limitedAccessNotEditable:
            return DetailsL10n.ClusterDetails.enhancementLimitedAccess
        case .originalUnavailable:
            return DetailsL10n.ClusterDetails.enhancementOriginalUnavailable
        case .renderFailed:
            return DetailsL10n.ClusterDetails.enhancementRenderFailed
        case .saveFailed:
            return DetailsL10n.ClusterDetails.enhancementSaveFailed
        case .notEnhancedByAlike:
            return DetailsL10n.ClusterDetails.enhancementNotOurs
        case .unsupportedAsset:
            return DetailsL10n.ClusterDetails.enhancementUnsupportedAsset
        case .editedInAnotherApp:
            return DetailsL10n.ClusterDetails.enhancementEditedElsewhere
        }
    }
}
