import SwiftUI
import Core
import Storage
import PhotoAnalysis

@MainActor
@Observable
public final class ScannerViewModel {
    public enum State: Equatable {
        case idle
        case scanning(progress: Double)
        case results([PhotoCluster])
        case error(String)
    }
    
    public var state: State = .idle
    public var gridColumns: Int
    public private(set) var reviewStates: [UUID: ClusterReviewState] = [:]
    public private(set) var activeCleanupSession: CleanupSession?
    
    private let analysisService: PhotoAnalysisService
    private let repository: PhotoClusterRepository
    private let reviewRepository: ClusterReviewStateRepository
    private let cleanupSessionRepository: CleanupSessionRepository
    public var sensitivity: SensitivityLevel
    
    public init(
        gridColumns: Int = 3,
        sensitivity: SensitivityLevel = .medium,
        analysisService: PhotoAnalysisService? = nil,
        repository: PhotoClusterRepository = CoreDataPhotoClusterRepository(),
        reviewRepository: ClusterReviewStateRepository = FileClusterReviewStateRepository(),
        cleanupSessionRepository: CleanupSessionRepository = FileCleanupSessionRepository()
    ) {
        self.gridColumns = gridColumns
        self.sensitivity = sensitivity
        self.repository = repository
        self.reviewRepository = reviewRepository
        self.cleanupSessionRepository = cleanupSessionRepository
        
        if let analysisService {
            self.analysisService = analysisService
        } else if let featurePrintRepository = repository as? PhotoFeaturePrintRepository {
            self.analysisService = PhotoAnalysisServiceImpl(featurePrintRepository: featurePrintRepository)
        } else {
            self.analysisService = PhotoAnalysisServiceImpl()
        }
    }
    
    public func loadCachedResults() async {
        do {
            let clusters = try await repository.loadClusters()
            if !clusters.isEmpty {
                let sorted = sortedClusters(from: clusters)
                if case .results(let existing) = state, existing == sorted {
                    return
                }
                AppLog.ui.debug("\(AppLog.tag(.cache, "Loaded cached clusters: \(sorted.count)"))")
                state = .results(sorted)
                await restoreActiveCleanupSession(for: sorted)
                await loadReviewStates(clusters: sorted)
            } else {
                await clearActiveCleanupSession()
            }
        } catch {
            AppLog.ui.error("\(AppLog.tag(.error, "Failed to load cached results: \(error.localizedDescription)"))")
        }
    }
    
    public func startScanning() async {
        AppLog.scan.info("\(AppLog.tag(.start, "Scan started"))")
        state = .scanning(progress: 0.0)
        
        do {
            let clusters = try await analysisService.analyzePhotoLibrary(
                sensitivity: sensitivity.threshold
            ) { progress in
                Task { @MainActor in
                    self.state = .scanning(progress: progress)
                }
            }
            
            // Save results
            try await repository.saveClusters(clusters)
            try await repository.updateLastScanDate(Date())
            
            let sorted = sortedClusters(from: clusters)
            if case .results(let existing) = state, existing == sorted {
                return
            }
            AppLog.scan.info("\(AppLog.tag(.finish, "Scan finished with clusters: \(sorted.count)"))")
            state = .results(sorted)
            await createNewCleanupSession(for: sorted)
            await loadReviewStates(clusters: sorted)
        } catch {
            AppLog.scan.error("\(AppLog.tag(.error, "Scan failed: \(error.localizedDescription)"))")
            state = .error(error.localizedDescription)
        }
    }
    
    public func checkForGalleryChanges() async -> Bool {
        await repository.hasGalleryChanged()
    }

    public func loadReviewStates() async {
        await loadReviewStates(clusters: currentResultClusters)
    }

    public func loadReviewStates(clusters: [PhotoCluster]) async {
        do {
            reviewStates = try await reviewRepository.loadAllReviewStates()
            await syncActiveCleanupSession(for: clusters)
        } catch {
            AppLog.ui.error("\(AppLog.tag(.error, "Failed to load review states: \(error.localizedDescription)"))")
            reviewStates = [:]
            await syncActiveCleanupSession(for: clusters)
        }
    }

    public func reviewState(for clusterID: UUID) -> ClusterReviewState? {
        reviewStates[clusterID]
    }

    public func reviewStatus(for clusterID: UUID) -> ClusterReviewStatus {
        reviewStates[clusterID]?.status ?? .notReviewed
    }

    public func sessionProgress(for clusters: [PhotoCluster]) -> CleanupSessionProgress {
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

    public func displayedSessionProgress(for clusters: [PhotoCluster]) -> CleanupSessionProgress {
        let computed = sessionProgress(for: clusters)
        if let activeCleanupSession, activeCleanupSession.totalClusters == clusters.count {
            return CleanupSessionProgress(
                totalClusters: activeCleanupSession.totalClusters,
                reviewedCount: activeCleanupSession.reviewedClusters,
                inReviewCount: computed.inReviewCount,
                notReviewedCount: computed.notReviewedCount,
                reviewedSavingsBytes: activeCleanupSession.estimatedSavingsBytes,
                totalSelectedItems: computed.totalSelectedItems
            )
        }
        return computed
    }

    public func cleanupEntryCluster(from clusters: [PhotoCluster]) -> PhotoCluster? {
        clusters.first(where: { reviewStatus(for: $0.id) == .notReviewed })
            ?? clusters.first(where: { reviewStatus(for: $0.id) == .inReview })
            ?? clusters.first
    }

    public func sortedClusters(from clusters: [PhotoCluster]) -> [PhotoCluster] {
        clusters.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            if $0.count != $1.count {
                return $0.count > $1.count
            }
            if $0.averageSimilarity != $1.averageSimilarity {
                return $0.averageSimilarity > $1.averageSimilarity
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

private extension ScannerViewModel {
    var currentResultClusters: [PhotoCluster] {
        if case .results(let clusters) = state {
            return clusters
        }
        return []
    }

    func createNewCleanupSession(for clusters: [PhotoCluster]) async {
        let now = Date()
        let session = CleanupSession(
            createdAt: now,
            updatedAt: now,
            totalClusters: clusters.count,
            reviewedClusters: 0,
            estimatedSavingsBytes: 0
        )

        do {
            try await cleanupSessionRepository.saveActiveSession(session)
            activeCleanupSession = session
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to save cleanup session: \(error.localizedDescription)"))"
            )
            activeCleanupSession = session
        }
    }

    func clearActiveCleanupSession() async {
        activeCleanupSession = nil
        do {
            try await cleanupSessionRepository.deleteActiveSession()
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to delete cleanup session: \(error.localizedDescription)"))"
            )
        }
    }

    func restoreActiveCleanupSession(for clusters: [PhotoCluster]) async {
        do {
            if let existing = try await cleanupSessionRepository.loadActiveSession(),
               existing.totalClusters == clusters.count {
                activeCleanupSession = existing
                return
            }
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to load cleanup session: \(error.localizedDescription)"))"
            )
        }

        await syncActiveCleanupSession(for: clusters)
    }

    func syncActiveCleanupSession(for clusters: [PhotoCluster]) async {
        guard !clusters.isEmpty else {
            await clearActiveCleanupSession()
            return
        }

        let progress = sessionProgress(for: clusters)
        let now = Date()
        let fallbackSession = CleanupSession(
            createdAt: now,
            updatedAt: now,
            totalClusters: clusters.count,
            reviewedClusters: progress.reviewedCount,
            estimatedSavingsBytes: progress.reviewedSavingsBytes
        )

        do {
            let loaded = try await cleanupSessionRepository.loadActiveSession()
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
                sessionToSave = fallbackSession
            }

            try await cleanupSessionRepository.saveActiveSession(sessionToSave)
            activeCleanupSession = sessionToSave
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to sync cleanup session: \(error.localizedDescription)"))"
            )
            activeCleanupSession = fallbackSession
        }
    }
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
