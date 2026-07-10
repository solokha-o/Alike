import Foundation
import Photos
import SwiftUI
import Core
import DesignSystem
import Storage

@MainActor
@Observable
final class ScreenshotCleanupViewModel {
    private let cleanupService: any PhotoCleanupService
    private let cleanupHistoryRepository: CleanupHistoryRepository
    private let openSettingsAction: (@MainActor @Sendable () -> Void)?
    private let assetSnapshots: [ReviewAssetSnapshot]
    let sourceCategory: CleanupCategoryKind

    var selectedAssetIDs: Set<String>
    private(set) var estimatedSavingsBytes: Int64
    var isDeleteConfirmationPresented = false
    private(set) var isDeleting = false
    private(set) var deleteErrorMessage: String?
    private(set) var shouldOfferOpenSettings = false
    private(set) var pendingCompletionRecord: CleanupCompletionRecord?

    init(
        assets: [PHAsset],
        sourceCategory: CleanupCategoryKind = .screenshots,
        cleanupService: any PhotoCleanupService = UnsupportedPhotoCleanupService(),
        cleanupHistoryRepository: CleanupHistoryRepository = FileCleanupHistoryRepository(),
        openSettingsAction: (@MainActor @Sendable () -> Void)? = nil,
        assetSnapshots: [ReviewAssetSnapshot]? = nil
    ) {
        self.cleanupService = cleanupService
        self.cleanupHistoryRepository = cleanupHistoryRepository
        self.openSettingsAction = openSettingsAction
        self.assetSnapshots = assetSnapshots ?? assets.map(ReviewAssetSnapshot.init)
        self.sourceCategory = sourceCategory
        self.selectedAssetIDs = []
        self.estimatedSavingsBytes = 0
    }

    var assetCount: Int {
        assetSnapshots.count
    }

    var presentation: CleanupCategoryPresentation {
        sourceCategory.presentation
    }

    var selectedCount: Int {
        selectedAssetIDs.count
    }

    var estimatedSavingsText: String {
        ByteCountFormatter.string(fromByteCount: estimatedSavingsBytes, countStyle: .file)
    }

    var isDeleteActionVisible: Bool {
        selectedCount > 0
    }

    func toggleSelection(for localIdentifier: String) {
        guard assetSnapshots.contains(where: { $0.localIdentifier == localIdentifier }) else { return }

        if selectedAssetIDs.contains(localIdentifier) {
            selectedAssetIDs.remove(localIdentifier)
        } else {
            selectedAssetIDs.insert(localIdentifier)
        }

        withAnimation(.appInteractive) {
            refreshDerivedState()
        }
    }

    func selectAll() {
        withAnimation(.appInteractive) {
            selectedAssetIDs = Set(assetSnapshots.map(\.localIdentifier))
            refreshDerivedState()
        }
    }

    func clearSelection() {
        withAnimation(.appInteractive) {
            selectedAssetIDs.removeAll()
            refreshDerivedState()
        }
    }

    func requestDeleteConfirmation() {
        guard isDeleteActionVisible, !isDeleting else { return }
        isDeleteConfirmationPresented = true
    }

    func confirmDelete() async {
        guard !isDeleting else { return }
        guard !selectedAssetIDs.isEmpty else {
            applyDeleteFailure(message: appLocalized("Select at least one photo before deleting."), offersOpenSettings: false)
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
                sourceClusterID: sourceCategory.sourceClusterID,
                estimatedSavingsBytes: estimatedSavingsBytes
            )

            do {
                try await cleanupHistoryRepository.append(record)
            } catch {
                AppLog.storage.error(
                    "\(AppLog.tag(.error, "Failed to persist cleanup history: \(error.localizedDescription)"))"
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

    func isSelected(_ localIdentifier: String) -> Bool {
        selectedAssetIDs.contains(localIdentifier)
    }
}

private extension ScreenshotCleanupViewModel {
    func refreshDerivedState() {
        estimatedSavingsBytes = assetSnapshots
            .filter { selectedAssetIDs.contains($0.localIdentifier) }
            .reduce(into: Int64(0)) { partialResult, snapshot in
                partialResult += snapshot.estimatedCleanupBytes
            }
    }

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
}
