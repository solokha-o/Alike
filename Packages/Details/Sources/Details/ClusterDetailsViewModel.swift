import Foundation
import Photos
import SwiftUI
import DesignSystem
import Storage

@MainActor
@Observable
final class ClusterDetailsViewModel {
    typealias AssetSnapshotLoader = @Sendable () async throws -> [ReviewAssetSnapshot]
    typealias AssetRefresher = @MainActor @Sendable (String) -> PHAsset?

    let cluster: PhotoCluster

    let reviewRepository: ClusterReviewStateRepository
    private let cleanupService: any PhotoCleanupService
    private let cleanupHistoryRepository: CleanupHistoryRepository
    private let premiumAccess: any PremiumAccessControlling
    private let openSettingsAction: (@MainActor @Sendable () -> Void)?
    private let completionDelay: @MainActor @Sendable () async -> Void
    private let assetSnapshotLoader: AssetSnapshotLoader
    /// Re-reads one asset from the library. `PHAsset` is a snapshot: after an
    /// edit lands, the copy the cluster was built from still reports the old
    /// `modificationDate`, which is what every image cache key is derived from.
    let assetRefresher: AssetRefresher
    let qualityAnalyzer: any PhotoQualityAnalyzing
    /// `nil` hides the enhancement action entirely, which is what previews and
    /// hosts without photo-library editing get.
    let enhancementService: (any PhotoEnhancementService)?
    /// Anonymous, on-device tally of how often our recommendation is replaced.
    let overrideMetrics: (any BestShotOverrideMetricsRepository)?
    /// The device's personalized Best Shot weights, applied on top of the
    /// global scoring config. `nil` in previews and hosts without a
    /// personalisation store, where ranking stays on the global config.
    /// Typed as the protocol, not the concrete
    /// `BestShotPersonalizedScoringConfigProvider`, so tests can substitute a
    /// double whose `config()` suspends on demand — the concrete actor caches
    /// for good after its first successful load, so it cannot be held open a
    /// second time the way a manual-pick-during-refine regression test needs.
    let personalizedConfigProvider: (any BestShotConfigProviding)?
    var assetSnapshots: [ReviewAssetSnapshot] = []
    /// Assets re-read after Alike edited them, by identifier. Keeping them here
    /// rather than mutating `cluster` leaves the cluster the value type it is.
    var refreshedAssets: [String: PHAsset] = [:]
    /// The scores the last ranking decision was made from, retained so a
    /// manual override afterwards can build its example from the same
    /// numbers the ranker saw — a cluster's worth, small.
    var qualityScores: [String: PhotoQualityScore] = [:]
    /// What the ranker recommended for the current `assetSnapshots`, before
    /// any manual override. Empty when nothing was ranked (no signals, or an
    /// unresolved decision).
    var rankedBestShotID = ""
    /// The config the last ranking decision was made under. An override
    /// example must be measured under the identical config, so this is
    /// captured once per decision rather than re-read from the provider —
    /// which could have moved on by the time the user overrides the pick.
    var rankedConfig: PhotoQualityScoringConfig = .current
    var persistenceTask: Task<Void, Never>?
    /// Bumped by every user action on this screen, so a slow ranking that
    /// arrives afterwards knows not to overwrite what the user just did.
    var interactionGeneration = 0
    var alikeReactionResolver = AlikeReactionResolver()
    let cleanupSelectionID = UUID()
    var reviewCompletionGeneration = 0
    var bestShotAssetID: String
    var bestShotLabel: String
    var isBestShotUserSelected = false
    /// How much the measured ranking trusts its own pick. A manual choice is
    /// always `.automatic`: the user is the authority.
    var bestShotConfidence: BestShotConfidence = .automatic
    var bestShotReasonCodes: [BestShotReasonCode] = []
    /// `true` between the metadata ranking appearing and the measured one
    /// landing. The badge waits it out: seeing the star jump from one photo to
    /// another is worse than seeing it a moment later.
    var isRankingQualityPending = false
    var enhancementState: PhotoEnhancementState = .unavailable
    /// The rendered "after" image. It lives only in memory: nothing is written
    /// to the library until the user applies the enhancement.
    var enhancementPreview: CGImage?
    /// Photos this screen enhanced. The badge follows the photo, so changing
    /// the Best Shot does not cancel or move an applied enhancement.
    var enhancedAssetIDs: Set<String> = []
    /// `true` when the Best Shot carries another app's edit: the action stays
    /// available, but the UI has to say what applying it would replace.
    var isBestShotEditedElsewhere = false
    /// Where the enhancement returns once the user dismisses the error alert.
    var enhancementRecoveryState: PhotoEnhancementState = .idle
    var selectedAssetIDs: Set<String>
    var reviewMode: ClusterReviewMode
    /// Set by the user finishing the review, never derived from how many photos
    /// are selected — keeping several photos, or all of them, is a decision too.
    var isReviewConfirmed = false
    var reviewStatus: ClusterReviewStatus
    var estimatedSavingsBytes: Int64
    private(set) var hasLoadedReviewState = false
    var isDeleteConfirmationPresented = false
    private(set) var isDeleting = false
    var actionErrorMessage: String?
    /// Which action failed — the alert must not call a failed enhancement a
    /// failed cleanup.
    var actionErrorTitle: String = DetailsL10n.Common.cleanupUnavailable
    var shouldOfferOpenSettings = false
    var pendingCompletionRecord: CleanupCompletionRecord?
    var currentAlikeReaction: AlikeReactionCue?
    var bestShotCelebrationCue: AlikeReviewReactionCue?
    /// Haptics are driven by these two counters, never by the values they
    /// describe. Opening a cluster restores the saved review and then refines
    /// the ranking in the background, so `selectedAssetIDs`, `bestShotAssetID`
    /// and `reviewStatus` all move without the user touching anything — the
    /// empty ID → metadata pick → measured pick sequence fired the confirmation
    /// pattern twice on a plain open. Only an explicit action bumps these.
    private(set) var selectionFeedbackTrigger = 0
    var successFeedbackTrigger = 0
    /// Increments once every persisted review-state write lands, so hosts can
    /// refresh their own snapshot of the review state while this screen is
    /// still visible instead of waiting for it to close.
    var persistedRevision = 0

    init(
        cluster: PhotoCluster,
        reviewRepository: ClusterReviewStateRepository = FileClusterReviewStateRepository(),
        cleanupService: any PhotoCleanupService = UnsupportedPhotoCleanupService(),
        cleanupHistoryRepository: CleanupHistoryRepository = FileCleanupHistoryRepository(),
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        openSettingsAction: (@MainActor @Sendable () -> Void)? = nil,
        qualityAnalyzer: any PhotoQualityAnalyzing = NoOpPhotoQualityAnalyzer(),
        enhancementService: (any PhotoEnhancementService)? = nil,
        overrideMetrics: (any BestShotOverrideMetricsRepository)? = nil,
        personalizedConfigProvider: (any BestShotConfigProviding)? = nil,
        assetSnapshots: [ReviewAssetSnapshot]? = nil,
        assetSnapshotLoader: AssetSnapshotLoader? = nil,
        completionDelay: @escaping @MainActor @Sendable () async -> Void = {
            try? await Task.sleep(for: .seconds(2))
        },
        assetRefresher: @escaping AssetRefresher = { localIdentifier in
            PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
        }
    ) {
        precondition(
            assetSnapshots == nil || assetSnapshotLoader == nil,
            "Provide assetSnapshots or assetSnapshotLoader, not both."
        )
        self.cluster = cluster
        self.reviewRepository = reviewRepository
        self.cleanupService = cleanupService
        self.cleanupHistoryRepository = cleanupHistoryRepository
        self.premiumAccess = premiumAccess
        self.openSettingsAction = openSettingsAction
        self.qualityAnalyzer = qualityAnalyzer
        self.enhancementService = enhancementService
        self.overrideMetrics = overrideMetrics
        self.personalizedConfigProvider = personalizedConfigProvider
        self.completionDelay = completionDelay
        self.assetRefresher = assetRefresher
        if let assetSnapshotLoader {
            self.assetSnapshotLoader = assetSnapshotLoader
        } else if let assetSnapshots {
            self.assetSnapshotLoader = { assetSnapshots }
        } else {
            self.assetSnapshotLoader = {
                try await Self.prepareAssetSnapshots(for: cluster)
            }
        }
        self.bestShotAssetID = ""
        self.bestShotLabel = DetailsL10n.Common.bestShot
        self.selectedAssetIDs = []
        self.reviewMode = .selection
        self.reviewStatus = .notReviewed
        self.estimatedSavingsBytes = 0
    }

    var selectedCount: Int {
        selectedAssetIDs.count
    }

    var assetCount: Int {
        assetSnapshots.count
    }

    var assets: [PHAsset] {
        guard !refreshedAssets.isEmpty else { return cluster.assets }
        return cluster.assets.map { refreshedAssets[$0.localIdentifier] ?? $0 }
    }

    var hasAssets: Bool {
        !assetSnapshots.isEmpty
    }

    var estimatedSavingsText: String {
        String.alikeByteCount(estimatedSavingsBytes)
    }

    var maximumEstimatedSavingsText: String {
        let maximumEstimatedSavingsBytes = assetSnapshots
            .filter { $0.localIdentifier != bestShotAssetID }
            .reduce(into: Int64(0)) { partialResult, snapshot in
                partialResult += snapshot.estimatedCleanupBytes
            }
        return String.alikeByteCount(maximumEstimatedSavingsBytes)
    }

    var isBestShotCelebrationVisible: Bool {
        assetCount > 1 && !bestShotAssetID.isEmpty && bestShotCelebrationCue != nil
    }

    var hasCompletedCleanup: Bool {
        pendingCompletionRecord != nil
    }

    var isActionBarVisible: Bool {
        assetSnapshots.count > 1 && (!bestShotAssetID.isEmpty || bestShotConfidence == .unresolved)
    }

    var isDeleteActionVisible: Bool {
        selectedCount > 0
    }

    var keptCount: Int {
        max(assetCount - selectedCount, 0)
    }

    /// Spells out what finishing the review would keep, so the icon-only
    /// confirmation button is unambiguous — especially with nothing selected,
    /// where it means "keep everything here".
    var keepSummaryText: String {
        guard selectedCount > 0 else {
            return String(format: DetailsL10n.Common.keepingAllPhotos, assetCount)
        }
        return String(format: DetailsL10n.ClusterDetails.keepingOf, keptCount, assetCount)
    }

    var requiresPremiumForCurrentSelection: Bool {
        !premiumAccess.access(
            to: .batchCleanup,
            context: .cleanupSelection(count: selectedCount)
        ).isAllowed
    }

    var displayedAssetIdentifiers: [String] {
        assetSnapshots.map(\.localIdentifier)
    }

    var displayedAssets: [PHAsset] {
        let displayedIDs = Set(displayedAssetIdentifiers)
        return assets.filter { displayedIDs.contains($0.localIdentifier) }
    }

    var deleteConfirmationTitle: String {
        DetailsL10n.ClusterDetails.deleteAlertTitle(selectedCount)
    }

    /// The body never prints the count, and `xcstringstool` rejects a plural variation whose text
    /// does not reference the number. Apple's guidance for that case is two top-level strings, so
    /// this one stays a pair; every shipped language reads its "greater than one" form above one.
    var deleteConfirmationMessage: String {
        let format = selectedCount == 1
            ? DetailsL10n.ClusterDetails.selectedPhotoWillBeRemoved
            : DetailsL10n.ClusterDetails.selectedPhotosWillBeRemoved
        return String(format: format, estimatedSavingsText)
    }

    var isActionErrorPresented: Bool {
        get { actionErrorMessage != nil }
        set {
            if !newValue {
                clearActionError()
            }
        }
    }

    func load() async {
        do {
            async let savedState = loadPersistedReviewState()
            let preparedSnapshots = try await assetSnapshotLoader()
            let persistedState = await savedState
            try Task.checkCancellation()

            // The screen appears on what is already known — the persisted review
            // and the metadata ranking. Quality scoring can decode photos and
            // fetch originals from iCloud; making the whole screen wait on that
            // would leave a spinner up for as long as the library is slow.
            await applyLoadedState(
                assetSnapshots: preparedSnapshots,
                savedState: persistedState,
                qualityScores: [:]
            )
            // The enhancement action follows the Best Shot that is on screen
            // now; the refinement below re-asks if the ranking moves it.
            await refreshEnhancementAvailability()
            isRankingQualityPending = true
            hasLoadedReviewState = true

            await refineWithQualityScores(
                assetSnapshots: preparedSnapshots,
                savedState: persistedState
            )
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            AppLog.ui.error("\(AppLog.tag(.error, "Failed to prepare cluster details: \(error.localizedDescription)"))")
            await applyLoadedState(assetSnapshots: [], savedState: nil)
            hasLoadedReviewState = true
        }
    }

    func toggleSelection(for localIdentifier: String) {
        interactionGeneration &+= 1
        // One photo of a cluster is always kept, and that photo is the Best
        // Shot. Until there is one, nothing here can be selected for deletion —
        // otherwise an unresolved cluster could be emptied completely.
        guard !bestShotAssetID.isEmpty else { return }
        guard localIdentifier != bestShotAssetID else { return }
        guard assetSnapshots.contains(where: { $0.localIdentifier == localIdentifier }) else { return }

        if selectedAssetIDs.contains(localIdentifier) {
            selectedAssetIDs.remove(localIdentifier)
        } else {
            selectedAssetIDs.insert(localIdentifier)
        }
        selectionFeedbackTrigger &+= 1

        withAnimation(.appInteractive) {
            isReviewConfirmed = false
            reviewMode = .selection
            refreshDerivedState(emitsReviewCompletion: true)
        }
        enqueueCurrentStatePersistence()
    }

    /// Finishes or reopens the review. Any set of kept photos is valid, so this
    /// is what marks the cluster reviewed — including the "keep everything,
    /// nothing to clean here" case where no photo is selected at all.
    func toggleReviewConfirmation() {
        interactionGeneration &+= 1
        // With no obvious Best Shot there is nothing to protect, but finishing
        // the review is still the user's call, so it stays available.
        guard !assetSnapshots.isEmpty else { return }
        guard !bestShotAssetID.isEmpty || bestShotConfidence == .unresolved else { return }

        withAnimation(.appInteractive) {
            isReviewConfirmed.toggle()
            reviewMode = .selection
            refreshDerivedState(emitsReviewCompletion: true)
        }
        enqueueCurrentStatePersistence()
    }

    /// Promotes `localIdentifier` to the best shot, keeping any review
    /// confirmation intact. The previous best shot only takes the promoted
    /// photo's place in the selection when the review kept nothing but the best
    /// shot; when the user deliberately kept several photos it stays kept.
    func setBestShot(_ localIdentifier: String) {
        interactionGeneration &+= 1
        guard localIdentifier != bestShotAssetID else { return }
        guard assetSnapshots.contains(where: { $0.localIdentifier == localIdentifier }) else { return }

        successFeedbackTrigger &+= 1
        let previousBestShotID = bestShotAssetID
        // Only a pick that replaces *our* recommendation is a calibration
        // signal; the user switching between their own picks is not.
        let replacedConfidence = isBestShotUserSelected ? nil : bestShotConfidence
        let keptBestShotOnly = isReviewConfirmed
            && selectedAssetIDs.count == assetSnapshots.count - 1

        withAnimation(.appInteractive) {
            selectedAssetIDs.remove(localIdentifier)
            if keptBestShotOnly, !previousBestShotID.isEmpty {
                selectedAssetIDs.insert(previousBestShotID)
            }
            bestShotAssetID = localIdentifier
            bestShotLabel = Self.bestShotLabel(for: localIdentifier, in: assetSnapshots)
            isBestShotUserSelected = true
            bestShotConfidence = .automatic
            bestShotReasonCodes = []
            isRankingQualityPending = false
            reviewMode = .selection
            refreshDerivedState(emitsReviewCompletion: true)
        }
        enqueueCurrentStatePersistence()
        Task { await refreshEnhancementAvailability() }
        if let replacedConfidence, let overrideMetrics {
            let clusterID = cluster.id
            Task {
                // The recommendation goes in first. The screen is interactive
                // before scoring finishes, so this override can be the thing
                // that happens before the recommendation was ever recorded —
                // and then neither side of the rate would exist. Recording is
                // deduped per cluster, so this is a no-op once it is counted.
                await overrideMetrics.recordRecommendation(
                    confidence: replacedConfidence,
                    clusterID: clusterID
                )
                await overrideMetrics.recordManualPick(
                    replacing: replacedConfidence,
                    clusterID: clusterID
                )
            }
        }
        // Same guard as the metrics tally above: only a pick that replaces
        // our recommendation is training data. Built from the scores and the
        // recommendation the ranking made this decision under, so a stale or
        // never-loaded ranking (`rankedBestShotID` empty) yields no example —
        // `overrideExample` requires `chosen != recommended` and refuses that
        // case on its own, but scores never having loaded also means there is
        // nothing meaningful to measure a delta from.
        if replacedConfidence != nil, let personalizedConfigProvider, !qualityScores.isEmpty {
            let snapshots = assetSnapshots.map(\.photoClusterAssetSnapshot)
            let scores = qualityScores
            let recommended = rankedBestShotID
            let config = rankedConfig
            Task {
                guard let example = BestShotRanker.overrideExample(
                    snapshots: snapshots,
                    scores: scores,
                    chosen: localIdentifier,
                    recommended: recommended,
                    config: config
                ) else { return }
                await personalizedConfigProvider.recordOverride(example)
            }
        }
    }

    func selectAllExceptBest() {
        interactionGeneration &+= 1
        guard !bestShotAssetID.isEmpty else { return }
        selectionFeedbackTrigger &+= 1
        withAnimation(.appInteractive) {
            selectedAssetIDs = Set(assetSnapshots.map(\.localIdentifier)).subtracting([bestShotAssetID])
            isReviewConfirmed = false
            reviewMode = .selection
            refreshDerivedState(emitsReviewCompletion: true)
        }
        enqueueCurrentStatePersistence()
    }

    func clearSelection() {
        interactionGeneration &+= 1
        selectionFeedbackTrigger &+= 1
        withAnimation(.appInteractive) {
            selectedAssetIDs.removeAll()
            isReviewConfirmed = false
            reviewMode = .selection
            refreshDerivedState(emitsReviewCompletion: true)
        }
        enqueueCurrentStatePersistence()
    }

    func continueWithSingleFreeSelection() async {
        guard
            let retainedID = assetSnapshots
                .map(\.localIdentifier)
                .first(where: selectedAssetIDs.contains)
        else { return }

        selectionFeedbackTrigger &+= 1
        withAnimation(.appInteractive) {
            selectedAssetIDs = [retainedID]
            isReviewConfirmed = false
            reviewMode = .selection
            refreshDerivedState(emitsReviewCompletion: true)
        }
        await save()
        isDeleteConfirmationPresented = true
    }

    func save() async {
        guard let task = enqueueCurrentStatePersistence() else { return }
        await task.value
    }

    /// Awaits the last enqueued persistence write, if any, without starting a
    /// new one. Callers that only need to know disk state is caught up (e.g.
    /// notifying a host before dismissal) should use this instead of `save()`.
    func awaitPendingPersistence() async {
        await persistenceTask?.value
    }

    @discardableResult
    func requestDeleteConfirmation() -> PremiumAccessDecision {
        guard isDeleteActionVisible, !isDeleting else { return .allowed }
        let decision = premiumAccess.access(
            to: .batchCleanup,
            context: .cleanupSelection(count: selectedCount)
        )
        guard decision.isAllowed else { return decision }
        isDeleteConfirmationPresented = true
        return .allowed
    }

    func confirmDelete() async {
        guard !isDeleting else { return }
        guard !selectedAssetIDs.isEmpty else {
            applyActionFailure(message: DetailsL10n.Common.selectAtLeastOnePhoto, offersOpenSettings: false)
            return
        }
        guard premiumAccess.access(
            to: .batchCleanup,
            context: .cleanupSelection(count: selectedCount)
        ).isAllowed else {
            isDeleteConfirmationPresented = false
            return
        }

        await persistenceTask?.value

        isDeleteConfirmationPresented = false
        actionErrorMessage = nil
        shouldOfferOpenSettings = false
        pendingCompletionRecord = nil
        isDeleting = true
        publishAlikeEvent(.cleanupStarted(id: cleanupSelectionID))

        do {
            let record = try await cleanupService.deleteAssets(
                localIdentifiers: selectedAssetIDs,
                sourceClusterID: cluster.id,
                estimatedSavingsBytes: estimatedSavingsBytes
            )

            do {
                try await cleanupHistoryRepository.append(record)
            } catch {
                AppLog.storage.error(
                    "\(AppLog.tag(.error, "Failed to persist cleanup history: \(error.localizedDescription)"))"
                )
            }

            do {
                try await reviewRepository.deleteReviewState(clusterID: cluster.id)
            } catch {
                AppLog.storage.error(
                    "\(AppLog.tag(.error, "Failed to delete review state after cleanup: \(error.localizedDescription)"))"
                )
            }

            await completionDelay()
            pendingCompletionRecord = record
        } catch let cleanupError as PhotoCleanupError {
            handleDeleteError(cleanupError)
        } catch {
            handleDeleteError(.deleteFailed)
        }

        isDeleting = false
    }

    func clearActionError() {
        if case .failed = enhancementState {
            enhancementState = enhancementRecoveryState
        }
        actionErrorMessage = nil
        actionErrorTitle = DetailsL10n.Common.cleanupUnavailable
        shouldOfferOpenSettings = false
        if let currentAlikeReaction,
           currentAlikeReaction.id.eventID == .cleanup(cleanupSelectionID) {
            publishAlikeEvent(.reactionConsumed(id: currentAlikeReaction.id))
        }
        publishCleanupSelectionReaction()
    }

    func openSettings() {
        openSettingsAction?()
    }

    func assetIndex(for localIdentifier: String) -> Int? {
        assets.firstIndex { $0.localIdentifier == localIdentifier }
    }

    func consumeBestShotCelebration(id: AlikeReviewReactionCue.ID) {
        guard bestShotCelebrationCue?.id == id else { return }
        bestShotCelebrationCue = nil
    }
}
