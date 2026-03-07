import Foundation
import Core

public protocol CleanupSessionManaging: Sendable {
    func startSession(totalClusters: Int) async -> CleanupSession
    func syncSession(
        for clusters: [PhotoCluster],
        reviewStates: [UUID: ClusterReviewState]
    ) async -> CleanupSession?
    func progress(
        for clusters: [PhotoCluster],
        reviewStates: [UUID: ClusterReviewState],
        activeSession: CleanupSession?
    ) -> CleanupSessionProgress
    func nextClusterToReview(
        from clusters: [PhotoCluster],
        reviewStates: [UUID: ClusterReviewState]
    ) -> PhotoCluster?
}

public struct CleanupSessionProgress: Equatable, Sendable {
    public let totalClusters: Int
    public let reviewedCount: Int
    public let inReviewCount: Int
    public let notReviewedCount: Int
    public let reviewedSavingsBytes: Int64
    public let totalSelectedItems: Int

    public var remainingClusters: Int {
        max(totalClusters - reviewedCount, 0)
    }

    public var reviewedRatio: Double {
        guard totalClusters > 0 else { return 0 }
        return Double(reviewedCount) / Double(totalClusters)
    }

    public var reviewedPercent: Int {
        Int((reviewedRatio * 100).rounded())
    }
}

public actor CleanupSessionManager: CleanupSessionManaging {
    private let repository: CleanupSessionRepository

    public init(repository: CleanupSessionRepository) {
        self.repository = repository
    }

    public func startSession(totalClusters: Int) async -> CleanupSession {
        let now = Date()
        let session = CleanupSession(
            createdAt: now,
            updatedAt: now,
            totalClusters: totalClusters,
            reviewedClusters: 0,
            estimatedSavingsBytes: 0
        )

        do {
            try await repository.saveActiveSession(session)
            return session
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to save cleanup session: \(error.localizedDescription)"))"
            )
            return session
        }
    }

    public func syncSession(
        for clusters: [PhotoCluster],
        reviewStates: [UUID: ClusterReviewState]
    ) async -> CleanupSession? {
        guard !clusters.isEmpty else {
            do {
                try await repository.deleteActiveSession()
            } catch {
                AppLog.storage.error(
                    "\(AppLog.tag(.error, "Failed to delete cleanup session: \(error.localizedDescription)"))"
                )
            }
            return nil
        }

        let progress = computedProgress(for: clusters, reviewStates: reviewStates)
        let now = Date()

        do {
            let loaded = try await repository.loadActiveSession()
            let sessionToSave: CleanupSession
            if let loaded, loaded.totalClusters == clusters.count {
                sessionToSave = CleanupSession(
                    id: loaded.id,
                    createdAt: loaded.createdAt,
                    updatedAt: now,
                    totalClusters: clusters.count,
                    reviewedClusters: progress.reviewedCount,
                    estimatedSavingsBytes: progress.reviewedSavingsBytes
                )
            } else {
                sessionToSave = CleanupSession(
                    createdAt: now,
                    updatedAt: now,
                    totalClusters: clusters.count,
                    reviewedClusters: progress.reviewedCount,
                    estimatedSavingsBytes: progress.reviewedSavingsBytes
                )
            }

            try await repository.saveActiveSession(sessionToSave)
            return sessionToSave
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to sync cleanup session: \(error.localizedDescription)"))"
            )
            return CleanupSession(
                createdAt: now,
                updatedAt: now,
                totalClusters: clusters.count,
                reviewedClusters: progress.reviewedCount,
                estimatedSavingsBytes: progress.reviewedSavingsBytes
            )
        }
    }

    public nonisolated func progress(
        for clusters: [PhotoCluster],
        reviewStates: [UUID: ClusterReviewState],
        activeSession: CleanupSession?
    ) -> CleanupSessionProgress {
        let computed = computedProgress(for: clusters, reviewStates: reviewStates)
        if let activeSession, activeSession.totalClusters == clusters.count {
            return CleanupSessionProgress(
                totalClusters: activeSession.totalClusters,
                reviewedCount: activeSession.reviewedClusters,
                inReviewCount: computed.inReviewCount,
                notReviewedCount: computed.notReviewedCount,
                reviewedSavingsBytes: activeSession.estimatedSavingsBytes,
                totalSelectedItems: computed.totalSelectedItems
            )
        }
        return computed
    }

    public nonisolated func nextClusterToReview(
        from clusters: [PhotoCluster],
        reviewStates: [UUID: ClusterReviewState]
    ) -> PhotoCluster? {
        clusters.first(where: { status(for: $0.id, reviewStates: reviewStates) == .notReviewed })
            ?? clusters.first(where: { status(for: $0.id, reviewStates: reviewStates) == .inReview })
            ?? clusters.first
    }
}

private extension CleanupSessionManager {
    nonisolated static func status(
        for clusterID: UUID,
        reviewStates: [UUID: ClusterReviewState]
    ) -> ClusterReviewStatus {
        reviewStates[clusterID]?.status ?? .notReviewed
    }

    nonisolated static func computedProgress(
        for clusters: [PhotoCluster],
        reviewStates: [UUID: ClusterReviewState]
    ) -> CleanupSessionProgress {
        var reviewedCount = 0
        var inReviewCount = 0
        var notReviewedCount = 0
        var reviewedSavingsBytes: Int64 = 0
        var totalSelectedItems = 0

        for cluster in clusters {
            let state = reviewStates[cluster.id]
            let status = state?.status ?? .notReviewed
            totalSelectedItems += state?.selectedLocalIdentifiers.count ?? 0

            switch status {
            case .reviewed:
                reviewedCount += 1
                reviewedSavingsBytes += state?.estimatedSavingsBytes ?? 0
            case .inReview:
                inReviewCount += 1
                reviewedSavingsBytes += state?.estimatedSavingsBytes ?? 0
            case .notReviewed:
                notReviewedCount += 1
            }
        }

        return CleanupSessionProgress(
            totalClusters: clusters.count,
            reviewedCount: reviewedCount,
            inReviewCount: inReviewCount,
            notReviewedCount: notReviewedCount,
            reviewedSavingsBytes: reviewedSavingsBytes,
            totalSelectedItems: totalSelectedItems
        )
    }

    nonisolated func status(
        for clusterID: UUID,
        reviewStates: [UUID: ClusterReviewState]
    ) -> ClusterReviewStatus {
        Self.status(for: clusterID, reviewStates: reviewStates)
    }

    nonisolated func computedProgress(
        for clusters: [PhotoCluster],
        reviewStates: [UUID: ClusterReviewState]
    ) -> CleanupSessionProgress {
        Self.computedProgress(for: clusters, reviewStates: reviewStates)
    }
}
