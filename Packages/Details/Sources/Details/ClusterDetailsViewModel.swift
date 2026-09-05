import Foundation
import Photos
import SwiftUI
import DesignSystem
import Storage

struct AlikeReviewReactionCue: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let clusterID: UUID
        let generation: Int
    }

    let id: ID
}

@MainActor
@Observable
final class ClusterDetailsViewModel {
    typealias AssetSnapshotLoader = @Sendable () async throws -> [ReviewAssetSnapshot]

    let cluster: PhotoCluster

    private let reviewRepository: ClusterReviewStateRepository
    private let cleanupService: any PhotoCleanupService
    private let cleanupHistoryRepository: CleanupHistoryRepository
    private let premiumAccess: any PremiumAccessControlling
    private let openSettingsAction: (@MainActor @Sendable () -> Void)?
    private let completionDelay: @MainActor @Sendable () async -> Void
    private let assetSnapshotLoader: AssetSnapshotLoader
    private let qualityAnalyzer: any PhotoQualityAnalyzing
    /// `nil` hides the enhancement action entirely, which is what previews and
    /// hosts without photo-library editing get.
    private let enhancementService: (any PhotoEnhancementService)?
    /// Anonymous, on-device tally of how often our recommendation is replaced.
    private let overrideMetrics: (any BestShotOverrideMetricsRepository)?
    /// The device's personalized Best Shot weights, applied on top of the
    /// global scoring config. `nil` in previews and hosts without a
    /// personalisation store, where ranking stays on the global config.
    /// Typed as the protocol, not the concrete
    /// `BestShotPersonalizedScoringConfigProvider`, so tests can substitute a
    /// double whose `config()` suspends on demand — the concrete actor caches
    /// for good after its first successful load, so it cannot be held open a
    /// second time the way a manual-pick-during-refine regression test needs.
    private let personalizedConfigProvider: (any BestShotConfigProviding)?
    private var assetSnapshots: [ReviewAssetSnapshot] = []
    /// The scores the last ranking decision was made from, retained so a
    /// manual override afterwards can build its example from the same
    /// numbers the ranker saw — a cluster's worth, small.
    private var qualityScores: [String: PhotoQualityScore] = [:]
    /// What the ranker recommended for the current `assetSnapshots`, before
    /// any manual override. Empty when nothing was ranked (no signals, or an
    /// unresolved decision).
    private var rankedBestShotID = ""
    /// The config the last ranking decision was made under. An override
    /// example must be measured under the identical config, so this is
    /// captured once per decision rather than re-read from the provider —
    /// which could have moved on by the time the user overrides the pick.
    private var rankedConfig: PhotoQualityScoringConfig = .current
    private var persistenceTask: Task<Void, Never>?
    /// Bumped by every user action on this screen, so a slow ranking that
    /// arrives afterwards knows not to overwrite what the user just did.
    private var interactionGeneration = 0
    private var alikeReactionResolver = AlikeReactionResolver()
    private let cleanupSelectionID = UUID()
    private var reviewCompletionGeneration = 0
    private(set) var bestShotAssetID: String
    private(set) var bestShotLabel: String
    private(set) var isBestShotUserSelected = false
    /// How much the measured ranking trusts its own pick. A manual choice is
    /// always `.automatic`: the user is the authority.
    private(set) var bestShotConfidence: BestShotConfidence = .automatic
    private(set) var bestShotReasonCodes: [BestShotReasonCode] = []
    /// `true` between the metadata ranking appearing and the measured one
    /// landing. The badge waits it out: seeing the star jump from one photo to
    /// another is worse than seeing it a moment later.
    private(set) var isRankingQualityPending = false
    private(set) var enhancementState: PhotoEnhancementState = .unavailable
    /// The rendered "after" image. It lives only in memory: nothing is written
    /// to the library until the user applies the enhancement.
    private(set) var enhancementPreview: CGImage?
    /// Photos this screen enhanced. The badge follows the photo, so changing
    /// the Best Shot does not cancel or move an applied enhancement.
    private(set) var enhancedAssetIDs: Set<String> = []
    /// `true` when the Best Shot carries another app's edit: the action stays
    /// available, but the UI has to say what applying it would replace.
    private(set) var isBestShotEditedElsewhere = false
    /// Where the enhancement returns once the user dismisses the error alert.
    private var enhancementRecoveryState: PhotoEnhancementState = .idle
    var selectedAssetIDs: Set<String>
    private(set) var reviewMode: ClusterReviewMode
    /// Set by the user finishing the review, never derived from how many photos
    /// are selected — keeping several photos, or all of them, is a decision too.
    private(set) var isReviewConfirmed = false
    private(set) var reviewStatus: ClusterReviewStatus
    private(set) var estimatedSavingsBytes: Int64
    private(set) var hasLoadedReviewState = false
    var isDeleteConfirmationPresented = false
    private(set) var isDeleting = false
    private(set) var actionErrorMessage: String?
    /// Which action failed — the alert must not call a failed enhancement a
    /// failed cleanup.
    private(set) var actionErrorTitle: String = DetailsL10n.Common.cleanupUnavailable
    private(set) var shouldOfferOpenSettings = false
    private(set) var pendingCompletionRecord: CleanupCompletionRecord?
    private(set) var currentAlikeReaction: AlikeReactionCue?
    private(set) var bestShotCelebrationCue: AlikeReviewReactionCue?
    /// Increments once every persisted review-state write lands, so hosts can
    /// refresh their own snapshot of the review state while this screen is
    /// still visible instead of waiting for it to close.
    private(set) var persistedRevision = 0

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
        cluster.assets
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
        enhancementState = .preparingPreview
        do {
            let preview = try await enhancementService.renderPreview(
                localIdentifier: localIdentifier,
                targetSize: previewSize
            )
            guard localIdentifier == bestShotAssetID else { return }
            enhancementPreview = preview
            enhancementState = .previewing
        } catch {
            guard localIdentifier == bestShotAssetID else { return }
            handleEnhancementError(error, fallbackState: .idle)
        }
    }

    func dismissEnhancementPreview() {
        guard enhancementState == .previewing else { return }
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

private extension ClusterDetailsViewModel {
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

    static func bestShotLocalIdentifier(from snapshots: [ReviewAssetSnapshot]) -> String? {
        PhotoClusterBestShot.bestShotLocalIdentifier(from: snapshots.map(\.photoClusterAssetSnapshot))
    }

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

actor UnsupportedPhotoCleanupService: PhotoCleanupService {
    func deleteAssets(
        localIdentifiers: Set<String>,
        sourceClusterID: UUID,
        estimatedSavingsBytes: Int64
    ) async throws -> CleanupCompletionRecord {
        throw PhotoCleanupError.deleteFailed
    }
}

struct ReviewAssetSnapshot: Equatable, Sendable {
    let localIdentifier: String
    let isFavorite: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let modificationDate: Date?

    init(asset: PHAsset) {
        self.localIdentifier = asset.localIdentifier
        self.isFavorite = asset.isFavorite
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.creationDate = asset.creationDate
        self.modificationDate = asset.modificationDate
    }

    init(
        localIdentifier: String,
        isFavorite: Bool,
        pixelWidth: Int,
        pixelHeight: Int,
        creationDate: Date?,
        modificationDate: Date? = nil
    ) {
        self.localIdentifier = localIdentifier
        self.isFavorite = isFavorite
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }

    var pixelArea: Int64 {
        Int64(pixelWidth) * Int64(pixelHeight)
    }

    var estimatedCleanupBytes: Int64 {
        max(1, pixelArea / 2)
    }

    var photoClusterAssetSnapshot: PhotoClusterAssetSnapshot {
        PhotoClusterAssetSnapshot(
            localIdentifier: localIdentifier,
            creationDate: creationDate,
            modificationDate: modificationDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            isFavorite: isFavorite
        )
    }
}
