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
    static func screenshotSnapshot(from snapshots: [CleanupCategoryAssetSnapshot]) -> CleanupCategorySnapshot? {
        let screenshotSnapshots = snapshots.filter(\.isScreenshot)
        guard !screenshotSnapshots.isEmpty else { return nil }

        let totalEstimatedSavings = screenshotSnapshots.reduce(into: Int64(0)) { partialResult, snapshot in
            partialResult += snapshot.estimatedCleanupBytes
        }

        return CleanupCategorySnapshot(
            kind: .screenshots,
            localIdentifiers: screenshotSnapshots.map(\.localIdentifier),
            assetCount: screenshotSnapshots.count,
            estimatedSavingsBytes: totalEstimatedSavings
        )
    }

    static func summaries(from snapshots: [CleanupCategorySnapshot]) -> [CleanupCategorySummary] {
        CleanupCategoryKind.allCases.compactMap { kind in
            snapshots.first(where: { $0.kind == kind })?.summary
        }
    }
}
