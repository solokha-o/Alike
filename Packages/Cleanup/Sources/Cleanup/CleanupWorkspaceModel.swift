import Core
import Foundation
import Observation
import PhotoAnalysis
import Photos
import Storage

/// Shared state for the Scanner and Cleanup tabs.
///
/// Scanner owns entitlement and allowance decisions. This model owns only the
/// library-derived Cleanup workspace, so reconciliation scans never affect a
/// user's scan allowance.
@MainActor
@Observable
public final class CleanupWorkspaceModel {
    public private(set) var contentState: CleanupContentState = .notLoaded
    public private(set) var scanOperation: ScanOperationState = .idle
    public private(set) var reconciliationState: CleanupReconciliationState?
    public private(set) var lastScanSummary: ScanSummary?
    public private(set) var lastCompletedScanDate: Date?
    public let cleanupService: any PhotoCleanupService
    public let cleanupHistoryRepository: any CleanupHistoryRepository

    public var content: CleanupWorkspaceContent? {
        guard lastGoodContent.hasCompletedScanBaseline else { return nil }
        return lastGoodContent
    }

    public var clusters: [PhotoCluster] { lastGoodContent.clusters }
    public var cleanupCategories: [CleanupCategorySummary] { lastGoodContent.categories }
    public var reviewStates: [UUID: ClusterReviewState] { lastGoodContent.reviewStates }
    public var resurfacingStates: [UUID: ClusterResurfacingState] {
        lastGoodContent.resurfacingStates
    }
    public var activeCleanupSession: CleanupSession? { lastGoodContent.activeSession }
    public var cleanupInsights: CleanupInsights { lastGoodContent.insights }
    public var hasCompletedScanBaseline: Bool { lastGoodContent.hasCompletedScanBaseline }
    public var shouldShowRescanPrompt: Bool { lastGoodContent.shouldShowRescanPrompt }

    private let analysisService: any PhotoAnalysisService
    private let repository: any PhotoClusterRepository
    private let reviewRepository: any ClusterReviewStateRepository
    private let cleanupCategoryRepository: any CleanupCategorySnapshotRepository
    private let cleanupManager: any CleanupSessionManaging
    private let cleanupInsightsProvider: any CleanupInsightsProviding
    private let now: @Sendable () -> Date

    private var lastGoodContent = CleanupWorkspaceContent.empty
    private var scanMutationGeneration = 0
    private var activeScanID: UUID?
    private var scanTask: Task<ScanSummary, Error>?
    private var reconciliationTask: Task<Void, Never>?
    private var activeReconciliation: (record: CleanupCompletionRecord, sensitivity: SensitivityLevel)?
    private var queuedReconciliation: (record: CleanupCompletionRecord, sensitivity: SensitivityLevel)?

    public init(
        analysisService: (any PhotoAnalysisService)? = nil,
        repository: any PhotoClusterRepository = CoreDataPhotoClusterRepository(),
        reviewRepository: any ClusterReviewStateRepository = FileClusterReviewStateRepository(),
        cleanupCategoryRepository: any CleanupCategorySnapshotRepository = FileCleanupCategorySnapshotRepository(),
        cleanupSessionRepository: any CleanupSessionRepository = FileCleanupSessionRepository(),
        cleanupService: any PhotoCleanupService = PhotoKitCleanupService(),
        cleanupHistoryRepository: any CleanupHistoryRepository = FileCleanupHistoryRepository(),
        cleanupManager: (any CleanupSessionManaging)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.reviewRepository = reviewRepository
        self.cleanupCategoryRepository = cleanupCategoryRepository
        self.cleanupService = cleanupService
        self.cleanupHistoryRepository = cleanupHistoryRepository
        self.cleanupManager = cleanupManager ?? CleanupSessionManager(repository: cleanupSessionRepository)
        self.cleanupInsightsProvider = CleanupInsightsService(repository: self.cleanupHistoryRepository)
        self.now = now

        if let analysisService {
            self.analysisService = analysisService
        } else if let featurePrintRepository = repository as? any PhotoFeaturePrintRepository {
            self.analysisService = PhotoAnalysisServiceImpl(
                featurePrintRepository: featurePrintRepository,
                cleanupCategoryRepository: cleanupCategoryRepository
            )
        } else {
            self.analysisService = PhotoAnalysisServiceImpl(
                cleanupCategoryRepository: cleanupCategoryRepository
            )
        }
    }

    /// Loads cached Cleanup data without starting a new scan.
    ///
    /// A stale cache load is discarded if a scan begins while its repositories
    /// are being read, preventing old data from replacing fresh scan results.
    public func loadCachedContent() async {
        let expectedGeneration = scanMutationGeneration
        let baselineDate = await repository.getLastScanDate()
        let insights = await fetchCleanupInsights()

        do {
            let loadedClusters = try await repository.loadClusters()
            let categories = await fetchCleanupCategories()
            let reviewData = await makeReviewData(for: loadedClusters)

            guard canCommitCachedLoad(expectedGeneration) else { return }

            let sortedClusters = canonicalSortedClusters(loadedClusters)
            let content = CleanupWorkspaceContent(
                clusters: sortedClusters,
                categories: categories,
                reviewStates: reviewData.states,
                resurfacingStates: reviewData.resurfacingStates,
                activeSession: reviewData.session,
                insights: insights,
                hasCompletedScanBaseline: baselineDate != nil,
                shouldShowRescanPrompt: false
            )
            lastGoodContent = content
            lastCompletedScanDate = baselineDate
            contentState = baselineDate == nil ? .neverScanned : .content(content)
        } catch {
            guard canCommitCachedLoad(expectedGeneration) else { return }
            lastCompletedScanDate = baselineDate
            if lastGoodContent.hasCompletedScanBaseline {
                contentState = .content(lastGoodContent)
            } else {
                contentState = .unavailable(message: error.localizedDescription)
            }
        }
    }

    /// Performs one user-requested library scan. Concurrent callers join the
    /// same single-flight operation and receive the same summary.
    @discardableResult
    public func scan(sensitivity: SensitivityLevel) async throws -> ScanSummary {
        try await startScan(sensitivity: sensitivity, purpose: .userInitiated)
    }

    /// Reconciles Cleanup after a deletion. Multiple completions are serialized
    /// and the latest queued record is processed after the active refresh.
    public func reconcile(
        after record: CleanupCompletionRecord,
        sensitivity: SensitivityLevel
    ) async {
        if reconciliationTask != nil {
            if activeReconciliation?.record != record {
                queuedReconciliation = (record, sensitivity)
            }
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runReconciliationQueue(initial: (record, sensitivity))
        }
        reconciliationTask = task
        await task.value
        reconciliationTask = nil
    }

    /// Reloads review state and updates Cleanup progress without reanalyzing
    /// the photo library.
    public func reloadReviewState() async {
        let expectedGeneration = scanMutationGeneration
        let reviewData = await makeReviewData(for: lastGoodContent.clusters)
        guard canCommitCachedLoad(expectedGeneration) else { return }

        let content = replacing(
            lastGoodContent,
            reviewStates: reviewData.states,
            resurfacingStates: reviewData.resurfacingStates,
            activeSession: reviewData.session
        )
        publish(content)
    }

    /// Updates the rescan prompt while preserving the current workspace.
    @discardableResult
    public func checkForGalleryChanges() async -> Bool {
        let expectedGeneration = scanMutationGeneration
        let hasChanged = await repository.hasGalleryChanged()
        guard canCommitCachedLoad(expectedGeneration) else { return false }
        let shouldPrompt = hasChanged && lastGoodContent.hasCompletedScanBaseline
        publish(replacing(lastGoodContent, shouldShowRescanPrompt: shouldPrompt))
        return shouldPrompt
    }

    public func reviewState(for clusterID: UUID) -> ClusterReviewState? {
        lastGoodContent.reviewStates[clusterID]
    }

    public func reviewStatus(for clusterID: UUID) -> ClusterReviewStatus {
        reviewState(for: clusterID)?.status ?? .notReviewed
    }

    public func resurfacingState(for clusterID: UUID) -> ClusterResurfacingState? {
        let state = lastGoodContent.resurfacingStates[clusterID] ?? .unchanged
        return state == .unchanged ? nil : state
    }

    public func needsReviewClusters() -> [PhotoCluster] {
        clusters.filter { reviewStatus(for: $0.id) == .needsReReview }
    }

    public func remainingClusters() -> [PhotoCluster] {
        clusters.filter { reviewStatus(for: $0.id) != .needsReReview }
    }

    public func sessionProgress() -> CleanupSessionProgress {
        cleanupManager.progress(
            for: clusters,
            reviewStates: reviewStates,
            activeSession: activeCleanupSession
        )
    }

    public func cleanupEntryCluster() -> PhotoCluster? {
        cleanupManager.nextClusterToReview(from: clusters, reviewStates: reviewStates)
    }

    public func loadAssets(for category: CleanupCategoryKind) async throws -> [PHAsset] {
        try await analysisService.loadAssets(for: category)
    }
}

private extension CleanupWorkspaceModel {
    func startScan(
        sensitivity: SensitivityLevel,
        purpose: ScanOperationPurpose
    ) async throws -> ScanSummary {
        if let scanTask {
            return try await scanTask.value
        }

        scanMutationGeneration &+= 1
        let scanID = UUID()
        activeScanID = scanID
        scanOperation = .scanning(progress: 0, purpose: purpose)

        let task = Task { @MainActor [weak self] () throws -> ScanSummary in
            guard let self else { throw CancellationError() }
            return try await self.performScan(
                sensitivity: sensitivity,
                purpose: purpose,
                scanID: scanID
            )
        }
        scanTask = task

        do {
            let summary = try await task.value
            if activeScanID == scanID {
                scanTask = nil
                activeScanID = nil
                scanOperation = .idle
            }
            return summary
        } catch {
            if activeScanID == scanID {
                scanTask = nil
                activeScanID = nil
                scanOperation = .failed(message: error.localizedDescription, purpose: purpose)
            }
            throw error
        }
    }

    func runReconciliationQueue(
        initial: (record: CleanupCompletionRecord, sensitivity: SensitivityLevel)
    ) async {
        var next: (record: CleanupCompletionRecord, sensitivity: SensitivityLevel)? = initial

        while let request = next {
            activeReconciliation = request
            queuedReconciliation = nil
            reconciliationState = .refreshing(request.record)

            do {
                _ = try await startScan(sensitivity: request.sensitivity, purpose: .reconciliation)
                reconciliationState = .success(request.record)
            } catch {
                let refreshedInsights = await fetchCleanupInsights()
                publish(replacing(lastGoodContent, insights: refreshedInsights))
                reconciliationState = .failed(
                    request.record,
                    message: "The photos were deleted, but the library refresh failed. Run a new scan to refresh your results."
                )
            }

            next = queuedReconciliation
        }

        activeReconciliation = nil
        queuedReconciliation = nil
    }

    func performScan(
        sensitivity: SensitivityLevel,
        purpose: ScanOperationPurpose,
        scanID: UUID
    ) async throws -> ScanSummary {
        let clustersBeforeScan = try await repository.loadClusters()
        let categorySnapshotsBeforeScan = try? await cleanupCategoryRepository.loadAllSnapshots()
        let previousSnapshots = try await repository.loadClusterSnapshots()
        let previousReviewStates = try await reviewRepository.loadAllReviewStates()

        let analyzedClusters = try await analysisService.analyzePhotoLibrary(
            sensitivity: sensitivity.threshold
        ) { [weak self] progress in
            Task { @MainActor in
                self?.updateScanProgress(progress, scanID: scanID, purpose: purpose)
            }
        }
        let refreshedCategories = try await analysisService.refreshCleanupCategories()

        let completedAt = now()
        do {
            try await repository.saveClusters(analyzedClusters)
            try await repository.updateLastScanDate(completedAt)
        } catch {
            await restorePersistedContent(
                clusters: clustersBeforeScan,
                categorySnapshots: categorySnapshotsBeforeScan
            )
            throw error
        }

        let sortedClusters = canonicalSortedClusters(analyzedClusters)
        let reviewData = await migratedReviewData(
            previousSnapshots: previousSnapshots,
            previousReviewStates: previousReviewStates,
            newClusters: sortedClusters
        )
        let session = await cleanupManager.syncSession(
            for: sortedClusters,
            reviewStates: reviewData.states
        )
        let insights = await fetchCleanupInsights()
        let content = CleanupWorkspaceContent(
            clusters: sortedClusters,
            categories: refreshedCategories,
            reviewStates: reviewData.states,
            resurfacingStates: reviewData.resurfacingStates,
            activeSession: session,
            insights: insights,
            hasCompletedScanBaseline: true,
            shouldShowRescanPrompt: false
        )
        publish(content)

        let categoryCandidateCount = refreshedCategories.reduce(0) { $0 + max($1.assetCount, 0) }
        let clusterSavings = sortedClusters.reduce(into: Int64(0)) { total, cluster in
            total += cluster.assets.reduce(into: Int64(0)) { $0 += $1.estimatedCleanupBytes }
        }
        let categorySavings = refreshedCategories.reduce(into: Int64(0)) { $0 += $1.estimatedSavingsBytes }
        let summary = ScanSummary(
            clusterCount: sortedClusters.count,
            cleanupCategoryCandidateCount: categoryCandidateCount,
            estimatedSavingsBytes: clusterSavings + categorySavings,
            completedAt: completedAt
        )
        lastScanSummary = summary
        lastCompletedScanDate = summary.completedAt
        return summary
    }

    func updateScanProgress(
        _ progress: Double,
        scanID: UUID,
        purpose: ScanOperationPurpose
    ) {
        guard activeScanID == scanID,
              case .scanning(let current, let activePurpose) = scanOperation,
              activePurpose == purpose else {
            return
        }
        scanOperation = .scanning(
            progress: max(current, min(max(progress, 0), 1)),
            purpose: purpose
        )
    }

    func migratedReviewData(
        previousSnapshots: [PhotoClusterSnapshot],
        previousReviewStates: [UUID: ClusterReviewState],
        newClusters: [PhotoCluster]
    ) async -> (
        states: [UUID: ClusterReviewState],
        resurfacingStates: [UUID: ClusterResurfacingState]
    ) {
        let result: ClusterReviewResurfacingResult
        if previousSnapshots.isEmpty {
            result = ClusterReviewResurfacingResult(
                migratedReviewStates: [:],
                resurfacingStates: Dictionary(
                    uniqueKeysWithValues: newClusters.map { ($0.id, .unchanged) }
                )
            )
        } else {
            result = ClusterReviewStateResurfacer.resurface(
                previousSnapshots: previousSnapshots,
                newClusters: newClusters,
                existingReviewStates: previousReviewStates
            )
        }

        do {
            try await persistReviewStates(result.migratedReviewStates)
        } catch {
            AppLog.storage.error(
                "Failed to persist migrated review states: \(error.localizedDescription)"
            )
        }
        return (result.migratedReviewStates, result.resurfacingStates)
    }

    func makeReviewData(for clusters: [PhotoCluster]) async -> (
        states: [UUID: ClusterReviewState],
        resurfacingStates: [UUID: ClusterResurfacingState],
        session: CleanupSession?
    ) {
        let states: [UUID: ClusterReviewState]
        do {
            states = try await reviewRepository.loadAllReviewStates()
        } catch {
            states = [:]
        }

        let resurfacingStates = Dictionary(uniqueKeysWithValues: clusters.map { cluster in
            (cluster.id, states[cluster.id]?.resurfacingState ?? .unchanged)
        })
        let session = await cleanupManager.syncSession(for: clusters, reviewStates: states)
        return (states, resurfacingStates, session)
    }

    func persistReviewStates(_ states: [UUID: ClusterReviewState]) async throws {
        try await reviewRepository.deleteAllReviewStates()
        for state in states.values {
            try await reviewRepository.saveReviewState(state)
        }
    }

    func restorePersistedContent(
        clusters: [PhotoCluster],
        categorySnapshots: [CleanupCategoryKind: CleanupCategorySnapshot]?
    ) async {
        do {
            try await repository.saveClusters(clusters)
        } catch {
            AppLog.storage.error("Failed to restore clusters after scan failure: \(error.localizedDescription)")
        }

        guard let categorySnapshots else { return }
        do {
            try await cleanupCategoryRepository.replaceAllSnapshots(Array(categorySnapshots.values))
        } catch {
            AppLog.storage.error("Failed to restore cleanup categories after scan failure: \(error.localizedDescription)")
        }
    }

    func fetchCleanupCategories() async -> [CleanupCategorySummary] {
        do {
            let snapshots = try await cleanupCategoryRepository.loadAllSnapshots()
            return CleanupCategoryKind.allCases.compactMap { snapshots[$0]?.summary }
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

    func canonicalSortedClusters(_ clusters: [PhotoCluster]) -> [PhotoCluster] {
        clusters.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            if lhs.averageSimilarity != rhs.averageSimilarity {
                return lhs.averageSimilarity > rhs.averageSimilarity
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func canCommitCachedLoad(_ expectedGeneration: Int) -> Bool {
        scanMutationGeneration == expectedGeneration && scanTask == nil
    }

    func publish(_ content: CleanupWorkspaceContent) {
        lastGoodContent = content
        contentState = content.hasCompletedScanBaseline ? .content(content) : .neverScanned
    }

    func replacing(
        _ content: CleanupWorkspaceContent,
        reviewStates: [UUID: ClusterReviewState]? = nil,
        resurfacingStates: [UUID: ClusterResurfacingState]? = nil,
        activeSession: CleanupSession?? = nil,
        insights: CleanupInsights? = nil,
        shouldShowRescanPrompt: Bool? = nil
    ) -> CleanupWorkspaceContent {
        CleanupWorkspaceContent(
            clusters: content.clusters,
            categories: content.categories,
            reviewStates: reviewStates ?? content.reviewStates,
            resurfacingStates: resurfacingStates ?? content.resurfacingStates,
            activeSession: activeSession ?? content.activeSession,
            insights: insights ?? content.insights,
            hasCompletedScanBaseline: content.hasCompletedScanBaseline,
            shouldShowRescanPrompt: shouldShowRescanPrompt ?? content.shouldShowRescanPrompt
        )
    }
}
