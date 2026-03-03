import Foundation
import Photos
import DesignSystem
import Storage

@MainActor
@Observable
final class ClusterDetailsViewModel {
    let cluster: PhotoCluster

    private let reviewRepository: ClusterReviewStateRepository
    private let assetSnapshots: [ReviewAssetSnapshot]

    private(set) var bestShotAssetID: String
    var selectedAssetIDs: Set<String>
    private(set) var reviewStatus: ClusterReviewStatus
    private(set) var estimatedSavingsBytes: Int64

    init(
        cluster: PhotoCluster,
        reviewRepository: ClusterReviewStateRepository = FileClusterReviewStateRepository(),
        assetSnapshots: [ReviewAssetSnapshot]? = nil
    ) {
        let resolvedSnapshots = assetSnapshots ?? cluster.assets.map(ReviewAssetSnapshot.init)
        self.cluster = cluster
        self.reviewRepository = reviewRepository
        self.assetSnapshots = resolvedSnapshots
        self.bestShotAssetID = Self.bestShotLocalIdentifier(from: resolvedSnapshots) ?? ""
        self.selectedAssetIDs = []
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

    func load() async {
        guard !assetSnapshots.isEmpty else {
            bestShotAssetID = ""
            selectedAssetIDs = []
            reviewStatus = .notReviewed
            estimatedSavingsBytes = 0
            return
        }

        let fallbackBestShotID = Self.bestShotLocalIdentifier(from: assetSnapshots) ?? ""

        do {
            guard let savedState = try await reviewRepository.loadReviewState(clusterID: cluster.id) else {
                applyState(bestShotAssetID: fallbackBestShotID, selectedAssetIDs: [])
                return
            }

            let validIDs = Set(assetSnapshots.map(\.localIdentifier))
            let persistedBestShotID = validIDs.contains(savedState.bestShotLocalIdentifier)
                ? savedState.bestShotLocalIdentifier
                : fallbackBestShotID
            let filteredSelection = savedState.selectedLocalIdentifiers
                .intersection(validIDs)
                .subtracting([persistedBestShotID])

            applyState(bestShotAssetID: persistedBestShotID, selectedAssetIDs: filteredSelection)
        } catch {
            AppLog.ui.error("\(AppLog.tag(.error, "Failed to load review state: \(error.localizedDescription)"))")
            applyState(bestShotAssetID: fallbackBestShotID, selectedAssetIDs: [])
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

        refreshDerivedState()
        persistCurrentState()
    }

    func selectAllExceptBest() {
        guard !bestShotAssetID.isEmpty else { return }
        selectedAssetIDs = Set(assetSnapshots.map(\.localIdentifier)).subtracting([bestShotAssetID])
        refreshDerivedState()
        persistCurrentState()
    }

    func keepBestOnly() {
        selectAllExceptBest()
    }

    func clearSelection() {
        selectedAssetIDs.removeAll()
        refreshDerivedState()
        persistCurrentState()
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
    func applyState(bestShotAssetID: String, selectedAssetIDs: Set<String>) {
        self.bestShotAssetID = bestShotAssetID
        self.selectedAssetIDs = selectedAssetIDs
        refreshDerivedState()
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

    func persistCurrentState() {
        guard !bestShotAssetID.isEmpty else { return }
        let state = ClusterReviewState(
            clusterID: cluster.id,
            bestShotLocalIdentifier: bestShotAssetID,
            selectedLocalIdentifiers: selectedAssetIDs,
            status: reviewStatus,
            estimatedSavingsBytes: estimatedSavingsBytes
        )

        Task {
            do {
                try await reviewRepository.saveReviewState(state)
            } catch {
                AppLog.storage.error("\(AppLog.tag(.error, "Failed to save review state: \(error.localizedDescription)"))")
            }
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
        snapshots.max(by: isPreferredAsset)?.localIdentifier
    }

    static func isPreferredAsset(_ lhs: ReviewAssetSnapshot, _ rhs: ReviewAssetSnapshot) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return !lhs.isFavorite && rhs.isFavorite
        }

        if lhs.pixelArea != rhs.pixelArea {
            return lhs.pixelArea < rhs.pixelArea
        }

        let lhsTimestamp = lhs.creationDate?.timeIntervalSince1970 ?? 0
        let rhsTimestamp = rhs.creationDate?.timeIntervalSince1970 ?? 0
        if lhsTimestamp != rhsTimestamp {
            return lhsTimestamp < rhsTimestamp
        }

        return lhs.localIdentifier > rhs.localIdentifier
    }
}

struct ReviewAssetSnapshot: Equatable, Sendable {
    let localIdentifier: String
    let isFavorite: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?

    init(asset: PHAsset) {
        self.localIdentifier = asset.localIdentifier
        self.isFavorite = asset.isFavorite
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.creationDate = asset.creationDate
    }

    init(
        localIdentifier: String,
        isFavorite: Bool,
        pixelWidth: Int,
        pixelHeight: Int,
        creationDate: Date?
    ) {
        self.localIdentifier = localIdentifier
        self.isFavorite = isFavorite
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.creationDate = creationDate
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
}
