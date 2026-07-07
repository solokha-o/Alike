import Foundation
import Photos
import Core

struct CleanupCategoryAssetSnapshot: Equatable, Sendable {
    let localIdentifier: String
    let isScreenshot: Bool
    let estimatedCleanupBytes: Int64

    init(localIdentifier: String, isScreenshot: Bool, estimatedCleanupBytes: Int64) {
        self.localIdentifier = localIdentifier
        self.isScreenshot = isScreenshot
        self.estimatedCleanupBytes = estimatedCleanupBytes
    }

    init(asset: PHAsset) {
        self.init(
            localIdentifier: asset.localIdentifier,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            estimatedCleanupBytes: asset.estimatedCleanupBytes
        )
    }
}

enum CleanupCategorySummaryBuilder {
    static func summaries(from snapshots: [CleanupCategoryAssetSnapshot]) -> [CleanupCategorySummary] {
        let screenshotSnapshots = snapshots.filter(\.isScreenshot)
        guard !screenshotSnapshots.isEmpty else { return [] }

        let totalEstimatedSavings = screenshotSnapshots.reduce(into: Int64(0)) { partialResult, snapshot in
            partialResult += snapshot.estimatedCleanupBytes
        }

        return [
            CleanupCategorySummary(
                kind: .screenshots,
                assetCount: screenshotSnapshots.count,
                estimatedSavingsBytes: totalEstimatedSavings
            )
        ]
    }
}
