import Foundation
import Photos
import SwiftUI
import DesignSystem
import Storage

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

    private(set) var bestShotAssetID: String
    var selectedAssetIDs: Set<String>
    private(set) var reviewMode: ClusterReviewMode
    private(set) var reviewStatus: ClusterReviewStatus
    private(set) var estimatedSavingsBytes: Int64
    var isDeleteConfirmationPresented = false
    private(set) var isDeleting = false
    private(set) var deleteErrorMessage: String?
    private(set) var shouldOfferOpenSettings = false
    private(set) var pendingCompletionRecord: CleanupCompletionRecord?

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

    var estimatedSavingsText: String {
        ByteCountFormatter.string(fromByteCount: estimatedSavingsBytes, countStyle: .file)
    }

    var bestShotLabel: String {
        assetSnapshots.first(where: { $0.localIdentifier == bestShotAssetID })?.title ?? appLocalized("Best Shot")
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

    func load() async {
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
            refreshDerivedState()
        }
        Task {
            await save()
        }
    }

    func selectAllExceptBest() {
        guard !bestShotAssetID.isEmpty else { return }
        withAnimation(.appInteractive) {
            selectedAssetIDs = Set(assetSnapshots.map(\.localIdentifier)).subtracting([bestShotAssetID])
            reviewMode = .selection
            refreshDerivedState()
        }
        Task {
            await save()
        }
    }

    func keepBestOnly() {
        guard !bestShotAssetID.isEmpty else { return }
        withAnimation(.appSmooth) {
            selectedAssetIDs = Set(assetSnapshots.map(\.localIdentifier)).subtracting([bestShotAssetID])
            reviewMode = .keepBestOnly
            refreshDerivedState()
        }
        Task {
            await save()
        }
    }

    func clearSelection() {
        withAnimation(.appInteractive) {
            selectedAssetIDs.removeAll()
            reviewMode = .selection
            refreshDerivedState()
        }
        Task {
            await save()
        }
    }

    func continueWithSingleFreeSelection() {
        guard
            let retainedID = assetSnapshots
                .map(\.localIdentifier)
                .first(where: selectedAssetIDs.contains)
        else { return }

        withAnimation(.appInteractive) {
            selectedAssetIDs = [retainedID]
            reviewMode = .selection
            refreshDerivedState()
        }
        isDeleteConfirmationPresented = true
        Task { await save() }
    }

    func save() async {
        await persistCurrentState()
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

        isDeleteConfirmationPresented = false
        deleteErrorMessage = nil
        shouldOfferOpenSettings = false
        pendingCompletionRecord = nil
        isDeleting = true

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
}

extension ClusterDetailsViewModel {
    func isBestShot(_ localIdentifier: String) -> Bool {
        bestShotAssetID == localIdentifier
    }

    func isSelected(_ localIdentifier: String) -> Bool {
        selectedAssetIDs.contains(localIdentifier)
    }

    func displayedAssets(from assets: [PHAsset]) -> [PHAsset] {
        let displayedIDs = Set(displayedAssetIdentifiers)
        return assets.filter { displayedIDs.contains($0.localIdentifier) }
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

    func refreshDerivedState() {
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
    }

    func persistCurrentState() async {
        guard !bestShotAssetID.isEmpty else { return }
        let state = ClusterReviewState(
            clusterID: cluster.id,
            bestShotLocalIdentifier: bestShotAssetID,
            selectedLocalIdentifiers: selectedAssetIDs,
            mode: reviewMode,
            status: reviewStatus,
            estimatedSavingsBytes: estimatedSavingsBytes,
            resurfacingState: reviewStatus == .needsReReview ? .changed : nil
        )

        do {
            try await reviewRepository.saveReviewState(state)
        } catch {
            AppLog.storage.error("\(AppLog.tag(.error, "Failed to save review state: \(error.localizedDescription)"))")
        }
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
