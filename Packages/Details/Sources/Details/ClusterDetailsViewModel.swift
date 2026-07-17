import Foundation
import Photos
import SwiftUI
import DesignSystem
import Storage

struct ALIReviewReactionCue: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let clusterID: UUID
        let generation: Int
    }

    let id: ID
}

@MainActor
@Observable
final class ClusterDetailsViewModel {
    let cluster: PhotoCluster

    private let reviewRepository: ClusterReviewStateRepository
    private let cleanupService: any PhotoCleanupService
    private let cleanupHistoryRepository: CleanupHistoryRepository
    private let premiumAccess: any PremiumAccessControlling
    private let openSettingsAction: (@MainActor @Sendable () -> Void)?
    private let assetSnapshots: [ReviewAssetSnapshot]
    private var persistenceTask: Task<Void, Never>?
    private var aliReactionResolver = ALIReactionResolver()
    private let cleanupSelectionID = UUID()
    private var reviewCompletionGeneration = 0
    private(set) var bestShotAssetID: String
    var selectedAssetIDs: Set<String>
    private(set) var reviewMode: ClusterReviewMode
    private(set) var reviewStatus: ClusterReviewStatus
    private(set) var estimatedSavingsBytes: Int64
    private(set) var hasLoadedReviewState = false
    var isDeleteConfirmationPresented = false
    private(set) var isDeleting = false
    private(set) var deleteErrorMessage: String?
    private(set) var shouldOfferOpenSettings = false
    private(set) var pendingCompletionRecord: CleanupCompletionRecord?
    private(set) var currentALIReaction: ALIReactionCue?
    private(set) var bestShotCelebrationCue: ALIReviewReactionCue?

    init(
        cluster: PhotoCluster,
        reviewRepository: ClusterReviewStateRepository = FileClusterReviewStateRepository(),
        cleanupService: any PhotoCleanupService = UnsupportedPhotoCleanupService(),
        cleanupHistoryRepository: CleanupHistoryRepository = FileCleanupHistoryRepository(),
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        openSettingsAction: (@MainActor @Sendable () -> Void)? = nil,
        assetSnapshots: [ReviewAssetSnapshot]? = nil
    ) {
        let resolvedSnapshots = assetSnapshots ?? cluster.assets.map(ReviewAssetSnapshot.init)
        self.cluster = cluster
        self.reviewRepository = reviewRepository
        self.cleanupService = cleanupService
        self.cleanupHistoryRepository = cleanupHistoryRepository
        self.premiumAccess = premiumAccess
        self.openSettingsAction = openSettingsAction
        self.assetSnapshots = resolvedSnapshots
        self.bestShotAssetID = Self.bestShotLocalIdentifier(from: resolvedSnapshots) ?? ""
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
        !assets.isEmpty
    }

    var estimatedSavingsText: String {
        ByteCountFormatter.string(fromByteCount: estimatedSavingsBytes, countStyle: .file)
    }

    var bestShotLabel: String {
        assetSnapshots.first(where: { $0.localIdentifier == bestShotAssetID })?.title ?? appLocalized("Best Shot")
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

    var requiresPremiumForCurrentSelection: Bool {
        !premiumAccess.access(
            to: .batchCleanup,
            context: .cleanupSelection(count: selectedCount)
        ).isAllowed
    }

    var displayedAssetIdentifiers: [String] {
        switch reviewMode {
        case .selection:
            assetSnapshots.map(\.localIdentifier)
        case .keepBestOnly:
            bestShotAssetID.isEmpty ? [] : [bestShotAssetID]
        }
    }

    var displayedAssets: [PHAsset] {
        let displayedIDs = Set(displayedAssetIdentifiers)
        return assets.filter { displayedIDs.contains($0.localIdentifier) }
    }

    var deleteConfirmationTitle: String {
        if selectedCount == 1 {
            return appLocalized("Move 1 Selected Photo to Recently Deleted?")
        }
        return String(
            format: appLocalized("Move %d Selected Photos to Recently Deleted?"),
            selectedCount
        )
    }

    var deleteConfirmationMessage: String {
        let format = selectedCount == 1
            ? appLocalized("The selected photo will be removed from your library and other devices using iCloud Photos, then remain in Recently Deleted for up to 30 days. Storage may not be freed until it is permanently deleted. Estimated reclaimable space: %@.")
            : appLocalized("The selected photos will be removed from your library and other devices using iCloud Photos, then remain in Recently Deleted for up to 30 days. Storage may not be freed until they are permanently deleted. Estimated reclaimable space: %@.")
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
        hasLoadedReviewState = false
        defer {
            hasLoadedReviewState = true
        }

        guard !assetSnapshots.isEmpty else {
            bestShotAssetID = ""
            selectedAssetIDs = []
            reviewMode = .selection
            reviewStatus = .notReviewed
            estimatedSavingsBytes = 0
            return
        }

        let fallbackBestShotID = Self.bestShotLocalIdentifier(from: assetSnapshots) ?? ""

        do {
            guard let savedState = try await reviewRepository.loadReviewState(clusterID: cluster.id) else {
                applyState(
                    bestShotAssetID: fallbackBestShotID,
                    selectedAssetIDs: [],
                    reviewMode: .selection,
                    persistedStatus: nil
                )
                return
            }

            let validIDs = Set(assetSnapshots.map(\.localIdentifier))
            let persistedBestShotID = validIDs.contains(savedState.bestShotLocalIdentifier)
                ? savedState.bestShotLocalIdentifier
                : fallbackBestShotID
            let filteredSelection = savedState.selectedLocalIdentifiers
                .intersection(validIDs)
                .subtracting([persistedBestShotID])

            applyState(
                bestShotAssetID: persistedBestShotID,
                selectedAssetIDs: filteredSelection,
                reviewMode: savedState.mode,
                persistedStatus: savedState.status
            )
        } catch {
            AppLog.ui.error("\(AppLog.tag(.error, "Failed to load review state: \(error.localizedDescription)"))")
            applyState(
                bestShotAssetID: fallbackBestShotID,
                selectedAssetIDs: [],
                reviewMode: .selection,
                persistedStatus: nil
            )
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
            reviewMode = .selection
            refreshDerivedState(emitsReviewCompletion: true)
        }
        enqueueCurrentStatePersistence()
    }

    func selectAllExceptBest() {
        guard !bestShotAssetID.isEmpty else { return }
        withAnimation(.appInteractive) {
            selectedAssetIDs = Set(assetSnapshots.map(\.localIdentifier)).subtracting([bestShotAssetID])
            reviewMode = .selection
            refreshDerivedState(emitsReviewCompletion: true)
        }
        enqueueCurrentStatePersistence()
    }

    func keepBestOnly() {
        guard !bestShotAssetID.isEmpty else { return }
        withAnimation(.appSmooth) {
            selectedAssetIDs = Set(assetSnapshots.map(\.localIdentifier)).subtracting([bestShotAssetID])
            reviewMode = .keepBestOnly
            refreshDerivedState(emitsReviewCompletion: true)
        }
        enqueueCurrentStatePersistence()
    }

    func clearSelection() {
        withAnimation(.appInteractive) {
            selectedAssetIDs.removeAll()
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
            applyDeleteFailure(message: appLocalized("Select at least one photo before deleting."), offersOpenSettings: false)
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
        publishALIEvent(.cleanupStarted(id: cleanupSelectionID))

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
    }

    func openSettings() {
        openSettingsAction?()
    }

    func assetIndex(for localIdentifier: String) -> Int? {
        assets.firstIndex { $0.localIdentifier == localIdentifier }
    }

    func consumeBestShotCelebration(id: ALIReviewReactionCue.ID) {
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
    func handleDeleteError(_ error: PhotoCleanupError) {
        switch error {
        case .nothingSelected:
            applyDeleteFailure(
                message: appLocalized("Select at least one photo before deleting."),
                offersOpenSettings: false
            )
        case .notAuthorized:
            applyDeleteFailure(
                message: appLocalized("Alike needs photo library access before it can delete photos. Open Settings to continue."),
                offersOpenSettings: true
            )
        case .selectedAssetsUnavailable:
            applyDeleteFailure(
                message: appLocalized("Some selected photos are no longer available. Your library access may be limited, or the library changed since the last scan."),
                offersOpenSettings: true
            )
        case .deleteFailed:
            applyDeleteFailure(
                message: appLocalized("Couldn't delete the selected photos. Please try again."),
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
        selectedAssetIDs: Set<String>,
        reviewMode: ClusterReviewMode,
        persistedStatus: ClusterReviewStatus?
    ) {
        self.bestShotAssetID = bestShotAssetID
        self.selectedAssetIDs = selectedAssetIDs
        self.reviewMode = reviewMode
        refreshDerivedState()
        if persistedStatus == .needsReReview {
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
            selectedAssetIDs: selectedAssetIDs,
            assetCount: assetSnapshots.count,
            bestShotAssetID: bestShotAssetID
        )

        if emitsReviewCompletion, previousStatus != .reviewed, reviewStatus == .reviewed {
            reviewCompletionGeneration &+= 1
            bestShotCelebrationCue = ALIReviewReactionCue(
                id: .init(clusterID: cluster.id, generation: reviewCompletionGeneration)
            )
        } else if reviewStatus != .reviewed {
            bestShotCelebrationCue = nil
        }

        if selectedAssetIDs.isEmpty {
            publishALIEvent(.cleanupSelectionCleared(id: cleanupSelectionID))
        } else {
            publishALIEvent(.cleanupReady(
                id: cleanupSelectionID,
                summary: ALICleanupSummary(
                    itemCount: selectedAssetIDs.count,
                    estimatedSavingsBytes: estimatedSavingsBytes
                )
            ))
        }
    }

    func publishALIEvent(_ event: ALIEvent) {
        _ = aliReactionResolver.apply(event)
        currentALIReaction = aliReactionResolver.currentCue
    }

    @discardableResult
    func enqueueCurrentStatePersistence() -> Task<Void, Never>? {
        guard !bestShotAssetID.isEmpty else { return nil }
        let state = ClusterReviewState(
            clusterID: cluster.id,
            bestShotLocalIdentifier: bestShotAssetID,
            selectedLocalIdentifiers: selectedAssetIDs,
            mode: reviewMode,
            status: reviewStatus,
            estimatedSavingsBytes: estimatedSavingsBytes,
            resurfacingState: reviewStatus == .needsReReview ? .changed : nil
        )
        let previousTask = persistenceTask
        let reviewRepository = reviewRepository

        let task = Task {
            await previousTask?.value
            do {
                try await reviewRepository.saveReviewState(state)
            } catch {
                AppLog.storage.error("\(AppLog.tag(.error, "Failed to save review state: \(error.localizedDescription)"))")
            }
        }
        persistenceTask = task
        return task
    }

    static func reviewStatus(
        selectedAssetIDs: Set<String>,
        assetCount: Int,
        bestShotAssetID: String
    ) -> ClusterReviewStatus {
        guard !selectedAssetIDs.isEmpty else { return .notReviewed }
        guard assetCount > 1, !bestShotAssetID.isEmpty else { return .notReviewed }

        let expectedSelectionCount = max(assetCount - 1, 0)
        return selectedAssetIDs.count == expectedSelectionCount ? .reviewed : .inReview
    }

    static func bestShotLocalIdentifier(from snapshots: [ReviewAssetSnapshot]) -> String? {
        PhotoClusterBestShot.bestShotLocalIdentifier(from: snapshots.map(\.photoClusterAssetSnapshot))
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

    var title: String {
        if let creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: creationDate)
        }
        return appLocalized("Best Shot")
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
