import Core
import Foundation

actor ScanPostProcessor {
    func prewarmByteSizes(for clusters: [PhotoCluster]) {
        AssetByteSize.prewarm(clusters.lazy.flatMap(\.assets))
    }

    /// Review states written with the pixel heuristic, re-measured against their
    /// cluster. States whose cluster is not loaded stay as they are until it is.
    func upgradingByteSizes(
        of states: [UUID: ClusterReviewState],
        clusters: [PhotoCluster]
    ) -> (states: [UUID: ClusterReviewState], upgraded: [ClusterReviewState]) {
        guard states.values.contains(where: { !$0.hasCurrentByteSizes }) else { return (states, []) }
        let clustersByID = Dictionary(clusters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = states
        var upgraded: [ClusterReviewState] = []
        for (id, state) in states where !state.hasCurrentByteSizes {
            guard let cluster = clustersByID[id] else { continue }
            let upgradedState = state.upgradingByteSizes(in: cluster)
            result[id] = upgradedState
            upgraded.append(upgradedState)
        }
        return (result, upgraded)
    }

    func remeasuringByteSizes(
        of snapshots: [CleanupCategorySnapshot],
        using bytesByIdentifier: @Sendable ([String]) -> [String: Int64]
    ) -> [CleanupCategorySnapshot] {
        snapshots.map { snapshot in
            guard !snapshot.hasCurrentByteSizes else { return snapshot }
            return snapshot.remeasured(bytesByIdentifier: bytesByIdentifier(snapshot.localIdentifiers))
        }
    }

    func canonicalSortedClusters(
        _ clusters: [PhotoCluster]
    ) -> [PhotoCluster] {
        clusters.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            if lhs.averageSimilarity != rhs.averageSimilarity {
                return lhs.averageSimilarity > rhs.averageSimilarity
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func migratedReviewStates(
        previousSnapshots: [PhotoClusterSnapshot],
        previousReviewStates: [UUID: ClusterReviewState],
        newClusters: [PhotoCluster]
    ) -> ClusterReviewResurfacingResult {
        guard !previousSnapshots.isEmpty else {
            return ClusterReviewResurfacingResult(
                migratedReviewStates: [:],
                resurfacingStates: Dictionary(
                    uniqueKeysWithValues: newClusters.map { ($0.id, .unchanged) }
                )
            )
        }
        return ClusterReviewStateResurfacer.resurface(
            previousSnapshots: previousSnapshots,
            newClusters: newClusters,
            existingReviewStates: previousReviewStates
        )
    }

    func categorySnapshots(
        persisted: [CleanupCategorySnapshot],
        refreshed: [CleanupCategorySummary],
        refreshedAt: Date
    ) -> [CleanupCategorySnapshot] {
        let persistedByKind = Dictionary(uniqueKeysWithValues: persisted.map { ($0.kind, $0) })
        return refreshed.map { summary in
            persistedByKind[summary.kind] ?? CleanupCategorySnapshot(
                kind: summary.kind,
                localIdentifiers: [],
                assetCount: summary.assetCount,
                estimatedSavingsBytes: summary.estimatedSavingsBytes,
                refreshedAt: refreshedAt
            )
        }
    }

    func resurfacingStates(
        for clusters: [PhotoCluster],
        reviewStates: [UUID: ClusterReviewState]
    ) -> [UUID: ClusterResurfacingState] {
        Dictionary(uniqueKeysWithValues: clusters.map { cluster in
            (cluster.id, reviewStates[cluster.id]?.resurfacingState ?? .unchanged)
        })
    }
}
