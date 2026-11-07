import Core
import Foundation
import Storage

extension CleanupWorkspaceModel {
    func persistMigratedReviewData(
        _ result: ClusterReviewResurfacingResult,
        clusters: [PhotoCluster]
    ) async -> (
        states: [UUID: ClusterReviewState],
        resurfacingStates: [UUID: ClusterResurfacingState]
    ) {
        let states = await postProcessor.upgradingByteSizes(
            of: result.migratedReviewStates,
            clusters: clusters
        ).states
        do {
            try await persistReviewStates(states)
        } catch {
            AppLog.storage.error(
                "Failed to persist migrated review states: \(error.localizedDescription)"
            )
        }
        return (states, result.resurfacingStates)
    }

    func makeReviewData(
        for clusters: [PhotoCluster],
        persistingRemeasurementsFor expectedGeneration: Int? = nil
    ) async -> (
        states: [UUID: ClusterReviewState],
        resurfacingStates: [UUID: ClusterResurfacingState],
        session: CleanupSession?
    ) {
        let states = await loadReviewStates()
        return await makeReviewData(
            for: clusters,
            reviewStates: states,
            persistingRemeasurementsFor: expectedGeneration
        )
    }

    func loadReviewStates() async -> [UUID: ClusterReviewState] {
        do {
            return try await reviewRepository.loadAllReviewStates()
        } catch {
            return [:]
        }
    }

    /// Legacy sums are re-measured and written back one state at a time. A cached
    /// load passes the generation it started at: once a scan has begun, the states
    /// it read belong to clusters the scan is replacing, and writing them back —
    /// even between the scan's own delete and save — would resurrect stale cluster
    /// IDs. Each write is re-checked, since a scan can start between two of them.
    func makeReviewData(
        for clusters: [PhotoCluster],
        reviewStates states: [UUID: ClusterReviewState],
        persistingRemeasurementsFor expectedGeneration: Int? = nil
    ) async -> (
        states: [UUID: ClusterReviewState],
        resurfacingStates: [UUID: ClusterResurfacingState],
        session: CleanupSession?
    ) {
        let upgrade = await postProcessor.upgradingByteSizes(of: states, clusters: clusters)
        for state in upgrade.upgraded {
            if let expectedGeneration, !canCommitCachedLoad(expectedGeneration) { break }
            do {
                try await reviewRepository.saveReviewState(state)
            } catch {
                AppLog.storage.error(
                    "Failed to persist re-measured review state: \(error.localizedDescription)"
                )
            }
        }
        let states = upgrade.states
        let resurfacingStates = await postProcessor.resurfacingStates(
            for: clusters,
            reviewStates: states
        )
        let session = await cleanupManager.syncSession(for: clusters, reviewStates: states)
        return (states, resurfacingStates, session)
    }

    private func persistReviewStates(_ states: [UUID: ClusterReviewState]) async throws {
        try await reviewRepository.deleteAllReviewStates()
        for state in states.values {
            try await reviewRepository.saveReviewState(state)
        }
    }

    func seedByteSizesIfNeeded() async {
        guard persistedByteSizeGeneration == nil else { return }
        AssetByteSize.seed(await assetByteSizeRepository.loadAll())
        persistedByteSizeGeneration = AssetByteSize.generation
    }

    /// Writes the sizes of every photo the content refers to, and only those, so
    /// deleted photos drop out of the store. Skipped when nothing was measured.
    func persistByteSizesIfNeeded(for content: CleanupWorkspaceContent) async {
        let generation = AssetByteSize.generation
        guard generation != persistedByteSizeGeneration else { return }
        let identifiers = content.clusters.flatMap { $0.assets.map(\.localIdentifier) }
            + content.categorySnapshots.flatMap(\.localIdentifiers)
        let records = AssetByteSize.records(for: identifiers)
        do {
            try await assetByteSizeRepository.replaceAll(records)
            persistedByteSizeGeneration = generation
        } catch {
            AppLog.storage.error("Failed to persist asset byte sizes: \(error.localizedDescription)")
        }
    }

    /// Categories in `CleanupCategoryKind.allCases` order, with their identifiers.
    /// A repository failure degrades to an empty section, never to a failed load.
    ///
    /// Legacy sums are re-measured and written back. A cached load passes the
    /// generation it started at: a scan that began meanwhile has already stored
    /// fresh categories, and writing the re-measured legacy ones over them would
    /// resurrect stale identifiers, so the write is skipped and the load's result
    /// is discarded by its own commit check.
    func fetchCleanupCategorySnapshots(
        persistingRemeasurementsFor expectedGeneration: Int? = nil
    ) async -> [CleanupCategorySnapshot] {
        do {
            let loaded = try await cleanupCategoryRepository.loadAllSnapshots()
            let snapshots = CleanupCategoryKind.allCases.compactMap { loaded[$0] }
            guard snapshots.contains(where: { !$0.hasCurrentByteSizes }) else { return snapshots }
            let remeasured = await postProcessor.remeasuringByteSizes(
                of: snapshots,
                using: assetBytesByIdentifier
            )
            if let expectedGeneration, !canCommitCachedLoad(expectedGeneration) {
                return remeasured
            }
            do {
                try await cleanupCategoryRepository.replaceAllSnapshots(remeasured)
            } catch {
                AppLog.storage.error("Failed to persist re-measured cleanup categories: \(error.localizedDescription)")
            }
            return remeasured
        } catch {
            AppLog.storage.error("Failed to load cleanup categories: \(error.localizedDescription)")
            return []
        }
    }

    func fetchCleanupInsights() async -> CleanupInsights {
        do {
            return try await cleanupInsightsProvider.loadInsights()
        } catch {
            AppLog.storage.error("Failed to load cleanup insights: \(error.localizedDescription)")
            return .empty
        }
    }
}
