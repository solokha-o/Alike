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
    private var assetSnapshots: [ReviewAssetSnapshot] = []
    private var persistenceTask: Task<Void, Never>?
    private var alikeReactionResolver = AlikeReactionResolver()
    private let cleanupSelectionID = UUID()
    private var reviewCompletionGeneration = 0
    private(set) var bestShotAssetID: String
    private(set) var bestShotLabel: String
    private(set) var isBestShotUserSelected = false
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
    private(set) var deleteErrorMessage: String?
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
        ByteCountFormatter.string(fromByteCount: estimatedSavingsBytes, countStyle: .file)
    }

    var maximumEstimatedSavingsText: String {
        let maximumEstimatedSavingsBytes = assetSnapshots
            .filter { $0.localIdentifier != bestShotAssetID }
            .reduce(into: Int64(0)) { partialResult, snapshot in
                partialResult += snapshot.estimatedCleanupBytes
            }
        return ByteCountFormatter.string(fromByteCount: maximumEstimatedSavingsBytes, countStyle: .file)
    }

    var isBestShotCelebrationVisible: Bool {
        assetCount > 1 && !bestShotAssetID.isEmpty && bestShotCelebrationCue != nil
    }

    var hasCompletedCleanup: Bool {
        pendingCompletionRecord != nil
    }

    var isActionBarVisible: Bool {
        assetSnapshots.count > 1 && !bestShotAssetID.isEmpty
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
        if selectedCount == 1 {
            return DetailsL10n.ClusterDetails.move1SelectedPhotoRecently
        }
        return String(
            format: DetailsL10n.ClusterDetails.moveSelectedPhotosRecentlyDeleted,
            selectedCount
        )
    }

    var deleteConfirmationMessage: String {
        let format = selectedCount == 1
            ? DetailsL10n.ClusterDetails.selectedPhotoWillBeRemoved
            : DetailsL10n.ClusterDetails.selectedPhotosWillBeRemoved
        return String(format: format, estimatedSavingsText)
    }

    var isDeleteErrorPresented: Bool {
        get { deleteErrorMessage != nil }
        set {
            if !newValue {
                clearDeleteError()
            }
        }
    }

    func load() async {
        do {
            async let savedState = loadPersistedReviewState()
            let preparedSnapshots = try await assetSnapshotLoader()
            let persistedState = await savedState
            try Task.checkCancellation()

            applyLoadedState(
                assetSnapshots: preparedSnapshots,
                savedState: persistedState
            )
            hasLoadedReviewState = true
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            AppLog.ui.error("\(AppLog.tag(.error, "Failed to prepare cluster details: \(error.localizedDescription)"))")
            applyLoadedState(assetSnapshots: [], savedState: nil)
            hasLoadedReviewState = true
        }
    }

    func toggleSelection(for localIdentifier: String) {
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
        guard !bestShotAssetID.isEmpty, !assetSnapshots.isEmpty else { return }

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
        guard localIdentifier != bestShotAssetID else { return }
        guard assetSnapshots.contains(where: { $0.localIdentifier == localIdentifier }) else { return }

        let previousBestShotID = bestShotAssetID
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
            reviewMode = .selection
            refreshDerivedState(emitsReviewCompletion: true)
        }
        enqueueCurrentStatePersistence()
    }

    func selectAllExceptBest() {
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
            applyDeleteFailure(message: DetailsL10n.Common.selectAtLeastOnePhoto, offersOpenSettings: false)
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
        deleteErrorMessage = nil
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

    func clearDeleteError() {
        deleteErrorMessage = nil
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

extension ClusterDetailsViewModel {
    func isBestShot(_ localIdentifier: String) -> Bool {
        bestShotAssetID == localIdentifier
    }

    func isSelected(_ localIdentifier: String) -> Bool {
        selectedAssetIDs.contains(localIdentifier)
    }

}

private extension ClusterDetailsViewModel {
    func loadPersistedReviewState() async -> ClusterReviewState? {
        do {
            return try await reviewRepository.loadReviewState(clusterID: cluster.id)
        } catch {
            AppLog.ui.error("\(AppLog.tag(.error, "Failed to load review state: \(error.localizedDescription)"))")
            return nil
        }
    }

    func applyLoadedState(
        assetSnapshots: [ReviewAssetSnapshot],
        savedState: ClusterReviewState?
    ) {
        self.assetSnapshots = assetSnapshots

        guard !assetSnapshots.isEmpty else {
            bestShotAssetID = ""
            bestShotLabel = DetailsL10n.Common.bestShot
            isBestShotUserSelected = false
            selectedAssetIDs = []
            isReviewConfirmed = false
            reviewMode = .selection
            reviewStatus = .notReviewed
            estimatedSavingsBytes = 0
            return
        }

        let fallbackBestShotID = Self.bestShotLocalIdentifier(from: assetSnapshots) ?? ""
        guard let savedState else {
            applyState(
                bestShotAssetID: fallbackBestShotID,
                isBestShotUserSelected: false,
                selectedAssetIDs: [],
                isReviewConfirmed: false,
                reviewMode: .selection,
                persistedStatus: nil
            )
            return
        }

        let validIDs = Set(assetSnapshots.map(\.localIdentifier))
        // A manual pick only survives while its photo does; once the photo is
        // gone the computed best shot takes over and stops being an override.
        let isPersistedBestShotAvailable = validIDs.contains(savedState.bestShotLocalIdentifier)
        let persistedBestShotID = isPersistedBestShotAvailable
            ? savedState.bestShotLocalIdentifier
            : fallbackBestShotID
        let filteredSelection = savedState.selectedLocalIdentifiers
            .intersection(validIDs)
            .subtracting([persistedBestShotID])

        applyState(
            bestShotAssetID: persistedBestShotID,
            isBestShotUserSelected: isPersistedBestShotAvailable && savedState.isBestShotUserSelected,
            selectedAssetIDs: filteredSelection,
            isReviewConfirmed: savedState.isReviewConfirmed,
            reviewMode: savedState.mode,
            persistedStatus: savedState.status
        )
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
            applyDeleteFailure(
                message: DetailsL10n.Common.selectAtLeastOnePhoto,
                offersOpenSettings: false
            )
        case .notAuthorized:
            applyDeleteFailure(
                message: DetailsL10n.Common.alikeNeedsPhotoLibraryAccess,
                offersOpenSettings: true
            )
        case .selectedAssetsUnavailable:
            applyDeleteFailure(
                message: DetailsL10n.Common.someSelectedPhotosNoLonger,
                offersOpenSettings: true
            )
        case .deleteFailed:
            applyDeleteFailure(
                message: DetailsL10n.Common.couldntDeleteSelectedPhotosPlease,
                offersOpenSettings: false
            )
        }
    }

    func applyDeleteFailure(message: String, offersOpenSettings: Bool) {
        deleteErrorMessage = message
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
            bestShotAssetID: bestShotAssetID
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
        guard !bestShotAssetID.isEmpty else { return nil }
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
        bestShotAssetID: String
    ) -> ClusterReviewStatus {
        guard assetCount > 0, !bestShotAssetID.isEmpty else { return .notReviewed }
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
        return creationDate.formatted(date: .abbreviated, time: .shortened)
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
