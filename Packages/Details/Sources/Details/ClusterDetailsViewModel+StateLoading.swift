import Foundation
import Photos
import SwiftUI
import DesignSystem
import Storage

extension ClusterDetailsViewModel {
    /// Re-applies the loaded state once the measured scores arrive, unless the
    /// user has already acted on the screen — their choice outranks a ranking
    /// that showed up late.
    func refineWithQualityScores(
        assetSnapshots: [ReviewAssetSnapshot],
        savedState: ClusterReviewState?
    ) async {
        let generation = interactionGeneration
        let qualityScores = await loadQualityScores()
        guard !Task.isCancelled else { return }
        guard generation == interactionGeneration else {
            isRankingQualityPending = false
            return
        }
        guard !qualityScores.isEmpty else {
            isRankingQualityPending = false
            await recordBestShotRecommendation()
            return
        }

        let didApply = await applyLoadedState(
            assetSnapshots: assetSnapshots,
            savedState: savedState,
            qualityScores: qualityScores,
            expectedGeneration: generation
        )
        // `applyLoadedState` itself suspends (the personalized config load);
        // a manual pick made during that suspension must win the same way one
        // made during `loadQualityScores` above already does.
        guard didApply else { return }
        isRankingQualityPending = false
        await refreshEnhancementAvailability()
        await recordBestShotRecommendation()
    }
}

private extension ClusterDetailsViewModel {
    /// Counts one recommendation per cluster — the repository dedupes revisits —
    /// and only when the ranking recommended something the user had not already
    /// chosen for themselves.
    func recordBestShotRecommendation() async {
        guard let overrideMetrics, !isBestShotUserSelected, !bestShotAssetID.isEmpty else { return }
        await overrideMetrics.recordRecommendation(
            confidence: bestShotConfidence,
            clusterID: cluster.id
        )
    }

    func loadQualityScores() async -> [String: PhotoQualityScore] {
        do {
            let scores = try await qualityAnalyzer.scores(for: cluster.assets)
            return Dictionary(scores.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })
        } catch is CancellationError {
            return [:]
        } catch {
            // Quality scoring is an improvement, not a requirement: without it
            // the metadata ranking still names a Best Shot.
            AppLog.ui.error(
                "\(AppLog.tag(.error, "Failed to score cluster photo quality: \(error.localizedDescription)"))"
            )
            return [:]
        }
    }
}

extension ClusterDetailsViewModel {
    func loadPersistedReviewState() async -> ClusterReviewState? {
        do {
            return try await reviewRepository.loadReviewState(clusterID: cluster.id)
        } catch {
            AppLog.ui.error("\(AppLog.tag(.error, "Failed to load review state: \(error.localizedDescription)"))")
            return nil
        }
    }

    /// - Parameter expectedGeneration: When non-`nil`, the `interactionGeneration`
    ///   the caller observed before starting the work that led here. Checked
    ///   again after this method's own suspension (the personalized config
    ///   load below) so a manual pick made while that was in flight is not
    ///   overwritten by the ranking this call is about to apply. `nil` (the
    ///   initial load, before the user can have acted yet) skips the check.
    /// - Returns: Whether the state was actually applied, `false` when a
    ///   newer interaction or cancellation won the race.
    @discardableResult
    func applyLoadedState(
        assetSnapshots: [ReviewAssetSnapshot],
        savedState: ClusterReviewState?,
        qualityScores: [String: PhotoQualityScore] = [:],
        expectedGeneration: Int? = nil
    ) async -> Bool {
        guard !assetSnapshots.isEmpty else {
            self.assetSnapshots = assetSnapshots
            self.qualityScores = qualityScores
            bestShotAssetID = ""
            bestShotLabel = DetailsL10n.Common.bestShot
            isBestShotUserSelected = false
            bestShotConfidence = .automatic
            bestShotReasonCodes = []
            selectedAssetIDs = []
            isReviewConfirmed = false
            reviewMode = .selection
            reviewStatus = .notReviewed
            estimatedSavingsBytes = 0
            rankedBestShotID = ""
            rankedConfig = .current
            return true
        }

        // The personalized config, when there is one: the details screen and
        // the grid must agree on which photo is the Best Shot, and an example
        // recorded later must be measured under the same config this decision
        // was made under.
        let config = await personalizedConfigProvider?.config() ?? .current
        guard !Task.isCancelled else { return false }
        // The config load above is itself a suspension point: a manual pick
        // made while it was in flight outranks the ranking this call is
        // about to apply, same as the `interactionGeneration` guard the
        // caller already made before starting this work. Nothing observable
        // (`assetSnapshots`, `qualityScores`, `enhancedAssetIDs`) is written
        // until this check passes, so `setBestShot`'s override example — built
        // from those same properties — never sees a ranking that is half this
        // call's and half the state the user actually picked against.
        if let expectedGeneration, expectedGeneration != interactionGeneration {
            isRankingQualityPending = false
            return false
        }
        self.assetSnapshots = assetSnapshots
        self.qualityScores = qualityScores
        // The measured decision; with no signals it degrades to exactly the
        // metadata-only ranking the app shipped before.
        // The badge belongs to the photo, not to this screen's lifetime: the
        // score cache remembers which photos Alike enhanced, so a photo that is
        // no longer the Best Shot keeps its badge after a reopen.
        enhancedAssetIDs = Set(
            qualityScores.values.filter(\.isAlikeEnhanced).map(\.localIdentifier)
        )
        self.rankedConfig = config
        let decision = BestShotRanker.decide(
            snapshots: assetSnapshots.map(\.photoClusterAssetSnapshot),
            scores: qualityScores,
            config: config
        )
        bestShotConfidence = decision.confidence
        bestShotReasonCodes = decision.reasonCodes
        let rankedBestShotID = decision.localIdentifier ?? ""
        self.rankedBestShotID = rankedBestShotID

        guard let savedState else {
            applyState(
                bestShotAssetID: rankedBestShotID,
                isBestShotUserSelected: false,
                selectedAssetIDs: [],
                isReviewConfirmed: false,
                reviewMode: .selection,
                persistedStatus: nil
            )
            return true
        }

        let validIDs = Set(assetSnapshots.map(\.localIdentifier))
        // A manual pick only survives while its photo does; once the photo is
        // gone the computed best shot takes over and stops being an override.
        let isPersistedBestShotAvailable = validIDs.contains(savedState.bestShotLocalIdentifier)
        let isManualOverride = isPersistedBestShotAvailable && savedState.isBestShotUserSelected
        let persistedBestShotID: String
        if isManualOverride {
            persistedBestShotID = savedState.bestShotLocalIdentifier
            // The user decided; the ranking does not get to hedge about it.
            bestShotConfidence = .automatic
            bestShotReasonCodes = []
        } else if isPersistedBestShotAvailable, savedState.isReviewConfirmed {
            // A finished review keeps the photo it was finished with, so a
            // rescan cannot silently move the Best Shot under a done cluster.
            // The badge and the summary card must then agree: this cluster has
            // a Best Shot, whatever the fresh ranking would have hedged.
            persistedBestShotID = savedState.bestShotLocalIdentifier
            bestShotConfidence = .automatic
            bestShotReasonCodes = []
        } else {
            persistedBestShotID = rankedBestShotID
        }
        // With no Best Shot there is no protected photo, so a stored selection
        // would be a ready-made way to delete every copy. It waits until the
        // user picks one.
        let filteredSelection = persistedBestShotID.isEmpty
            ? []
            : savedState.selectedLocalIdentifiers
                .intersection(validIDs)
                .subtracting([persistedBestShotID])

        applyState(
            bestShotAssetID: persistedBestShotID,
            isBestShotUserSelected: isManualOverride,
            selectedAssetIDs: filteredSelection,
            isReviewConfirmed: savedState.isReviewConfirmed,
            reviewMode: savedState.mode,
            persistedStatus: savedState.status
        )
        return true
    }
}
