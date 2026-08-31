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
    /// Best Shot quality scoring, cached in Core Data so reopening a cluster
    /// does not decode its photos again.
    public let qualityAnalyzer: any PhotoQualityAnalyzing

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
    private let postProcessor = ScanPostProcessor()

    private var lastGoodContent = CleanupWorkspaceContent.empty

    /// Derived from `lastGoodContent` and refreshed only when it is replaced.
    ///
    /// `CleanupView` reads all three during `body`, where an O(clusters) pass
    /// would re-run on every unrelated state flip — opening the filter sheet,
    /// dismissing an alert. Their inputs live entirely in `lastGoodContent`, so
    /// recomputing where it is published is equivalent and happens far less
    /// often. They stay observable stored properties, so views still update.
    private(set) var sessionProgressSnapshot: CleanupSessionProgress = .empty
    private(set) var cleanupEntryClusterSnapshot: PhotoCluster?
    private(set) var clusterIdentityKey: [UUID] = []
    private var scanMutationGeneration = 0
    private var cachedContentLoadTask: Task<Void, Never>?
    private var activeScan: (id: UUID, sensitivity: SensitivityLevel, purpose: ScanOperationPurpose)?
    private var scanTask: Task<ScanSummary, Error>?
    private var progressRelay: ScanProgressRelay?
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
        qualityAnalyzer: any PhotoQualityAnalyzing = CachingPhotoQualityAnalyzer(
            repository: CoreDataPhotoQualityScoreRepository()
        ),
        cleanupManager: (any CleanupSessionManaging)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.reviewRepository = reviewRepository
        self.cleanupCategoryRepository = cleanupCategoryRepository
        self.cleanupService = cleanupService
        self.cleanupHistoryRepository = cleanupHistoryRepository
        self.qualityAnalyzer = qualityAnalyzer
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
    /// Repeated callers reuse the first load so tab appearances do not rebuild
    /// an already-published workspace from disk.
    ///
    /// A stale cache load is discarded if a scan begins while its repositories
    /// are being read, preventing old data from replacing fresh scan results.
    public func loadCachedContent() async {
        guard contentState == .notLoaded else { return }

        if let cachedContentLoadTask {
            await cachedContentLoadTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCachedContentLoad()
        }
        cachedContentLoadTask = task
        await task.value
        cachedContentLoadTask = nil
    }

    private func performCachedContentLoad() async {
        let expectedGeneration = scanMutationGeneration
        let baselineDate = await repository.getLastScanDate()
        let insights = await fetchCleanupInsights()

        do {
            let loadedClusters = try await repository.loadClusters()
            let categories = await fetchCleanupCategories()
            let reviewData = await makeReviewData(for: loadedClusters)

            guard canCommitCachedLoad(expectedGeneration) else { return }

            let sortedClusters = await postProcessor.canonicalSortedClusters(loadedClusters)
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
            refreshDerivedContentSnapshots()
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

    /// Performs one user-requested library scan. Concurrent callers of matching
    /// sensitivity join the same single-flight operation and receive the same
    /// summary; a request at a different sensitivity waits for the in-flight
    /// operation and then runs fresh work at the sensitivity it asked for.
    @discardableResult
    public func scan(sensitivity: SensitivityLevel) async throws -> ScanSummary {
        try await startScan(sensitivity: sensitivity, purpose: .userInitiated).summary
    }

    /// Same as ``scan(sensitivity:)`` but also reports whether the request
    /// joined an in-flight scan of matching sensitivity rather than running
    /// fresh work. Callers that charge a scan allowance for fresh work only
    /// (e.g. Scanner) need this distinction — a pre-call check of whether a
    /// reconciliation was in flight can't tell whether the call actually
    /// joined it or ended up running its own scan at a different sensitivity.
    @discardableResult
    public func scanReportingJoinedOperation(
        sensitivity: SensitivityLevel
    ) async throws -> ScanOutcome {
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
        let reviewStates = await loadReviewStates()
        guard canCommitCachedLoad(expectedGeneration) else { return }
        guard reviewStates != lastGoodContent.reviewStates else { return }

        let reviewData = await makeReviewData(
            for: lastGoodContent.clusters,
            reviewStates: reviewStates
        )
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
        if shouldPrompt != lastGoodContent.shouldShowRescanPrompt {
            publish(replacing(lastGoodContent, shouldShowRescanPrompt: shouldPrompt))
        }
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

    public func sessionProgress() -> CleanupSessionProgress { sessionProgressSnapshot }

    public func cleanupEntryCluster() -> PhotoCluster? { cleanupEntryClusterSnapshot }

    public func loadAssets(for category: CleanupCategoryKind) async throws -> [PHAsset] {
        try await analysisService.loadAssets(for: category)
    }

    /// Quiesces every workspace operation before app-owned persistence is erased.
    /// Awaiting cancelled work prevents a late scan completion from recreating
    /// data after the deletion service has finished.
    public func prepareForDataDeletion() async {
        scanMutationGeneration &+= 1

        let cachedLoad = cachedContentLoadTask
        let activeScanTask = scanTask
        let activeReconciliationTask = reconciliationTask

        cachedLoad?.cancel()
        activeScanTask?.cancel()
        activeReconciliationTask?.cancel()
        await progressRelay?.cancel()

        await cachedLoad?.value
        _ = try? await activeScanTask?.value
        await activeReconciliationTask?.value

        cachedContentLoadTask = nil
        scanTask = nil
        reconciliationTask = nil
        progressRelay = nil
        activeScan = nil
        activeReconciliation = nil
        queuedReconciliation = nil
        lastGoodContent = .empty
        refreshDerivedContentSnapshots()
        contentState = .neverScanned
        scanOperation = .idle
        reconciliationState = nil
        lastScanSummary = nil
        lastCompletedScanDate = nil
    }
}

private extension CleanupWorkspaceModel {
    /// Joins an in-flight scan only when it is analyzing at the same
    /// sensitivity the caller asked for; a request at a different sensitivity
    /// would otherwise silently report a summary computed at the wrong
    /// sensitivity. A mismatched request instead waits for the in-flight scan
    /// to finish and then runs its own, so the caller's chosen sensitivity is
    /// always honored.
    func startScan(
        sensitivity: SensitivityLevel,
        purpose: ScanOperationPurpose
    ) async throws -> ScanOutcome {
        try Task.checkCancellation()

        // Loops rather than checking once: two mismatched requests can both be
        // waiting on the same in-flight scan, and the one that resumes second
        // must wait for the scan the first one started instead of racing it.
        // Awaiting a task that is already finished returns immediately, so the
        // identity check below is what guarantees the loop terminates.
        while let inFlight = scanTask {
            if activeScan?.sensitivity == sensitivity {
                if purpose == .userInitiated, activeScan?.purpose == .reconciliation {
                    reflectUserInitiatedJoin()
                }
                let summary = try await inFlight.value
                return ScanOutcome(summary: summary, joinedInFlightOperation: true)
            }
            _ = try? await inFlight.value
            if scanTask == inFlight { break }
        }

        scanMutationGeneration &+= 1
        let scanID = UUID()
        activeScan = (scanID, sensitivity, purpose)
        scanOperation = .scanning(progress: 0, purpose: purpose)
        // A scan whose owner has not finished its own cleanup yet leaves its
        // relay behind; cancel it so it stops forwarding into a scan that is
        // no longer the active one.
        await progressRelay?.cancel()
        progressRelay = ScanProgressRelay { [weak self] progress in
            self?.publishScanProgress(progress, scanID: scanID)
        }

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
            if activeScan?.id == scanID {
                await progressRelay?.cancel()
                progressRelay = nil
                scanTask = nil
                activeScan = nil
                scanOperation = .idle
            }
            return ScanOutcome(summary: summary, joinedInFlightOperation: false)
        } catch {
            if activeScan?.id == scanID {
                await progressRelay?.cancel()
                progressRelay = nil
                scanTask = nil
                let failurePurpose = activeScan?.purpose ?? purpose
                activeScan = nil
                scanOperation = .failed(message: error.localizedDescription, purpose: failurePurpose)
            }
            throw error
        }
    }

    /// Flips the currently active scan's displayed purpose to `.userInitiated`
    /// when a user scan joins a still-running reconciliation, so the UI shows
    /// scanning rather than refreshing for the rest of that operation.
    func reflectUserInitiatedJoin() {
        guard var current = activeScan, current.purpose == .reconciliation else { return }
        current.purpose = .userInitiated
        activeScan = current
        if case .scanning(let progress, _) = scanOperation {
            scanOperation = .scanning(progress: progress, purpose: .userInitiated)
        }
    }

    func runReconciliationQueue(
        initial: (record: CleanupCompletionRecord, sensitivity: SensitivityLevel)
    ) async {
        var next: (record: CleanupCompletionRecord, sensitivity: SensitivityLevel)? = initial

        while let request = next {
            guard !Task.isCancelled else { break }
            activeReconciliation = request
            queuedReconciliation = nil
            reconciliationState = .refreshing(request.record)

            do {
                _ = try await startScan(sensitivity: request.sensitivity, purpose: .reconciliation)
                reconciliationState = .success(request.record)
            } catch {
                guard !Task.isCancelled else { break }
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
        let scanMetadataBeforeScan = await repository.loadScanMetadata()
        let previousSnapshots = try await repository.loadClusterSnapshots()
        let previousReviewStates = try await reviewRepository.loadAllReviewStates()

        guard let progressRelay else { throw CancellationError() }
        // Captured now, immediately before analysis takes its own snapshot of
        // the library's assets. A photo added or removed while Vision/category
        // work is running would otherwise be included in a late token/count
        // while remaining absent from the clusters that work produces, so the
        // next change check would see no delta and never prompt for the rescan
        // that photo actually requires.
        let capturedFingerprint = await repository.captureScanMetadata(completedAt: now())
        let analyzedClusters = try await analysisService.analyzePhotoLibrary(
            sensitivity: sensitivity.threshold
        ) { progress in
            Task { await progressRelay.submit(ScanProgressStages.analysis(progress)) }
        }
        try Task.checkCancellation()
        await progressRelay.submit(ScanProgressStages.analysis(1), force: true)
        let refreshedCategories = try await analysisService.refreshCleanupCategories { progress in
            Task { await progressRelay.submit(ScanProgressStages.categories(progress)) }
        }
        try Task.checkCancellation()
        await progressRelay.submit(ScanProgressStages.persistenceStart, force: true)

        let completedAt: Date
        do {
            try await repository.saveClusters(analyzedClusters)
            // The fingerprint itself was captured before analysis started, so it
            // matches the asset input the persisted clusters were derived from.
            // Only the completion timestamp is stamped now, and the pairing is
            // persisted only after a successful scan — a failed scan below must
            // not advance the baseline past clusters that were never saved.
            completedAt = now()
            try await repository.updateScanMetadata(
                ScanMetadataSnapshot(
                    lastScanDate: completedAt,
                    libraryChangeToken: capturedFingerprint.libraryChangeToken,
                    imageAssetCount: capturedFingerprint.imageAssetCount
                )
            )
            try Task.checkCancellation()
        } catch {
            await restorePersistedContent(
                clusters: clustersBeforeScan,
                categorySnapshots: categorySnapshotsBeforeScan,
                scanMetadata: scanMetadataBeforeScan
            )
            throw error
        }

        let sortedClusters = await postProcessor.canonicalSortedClusters(analyzedClusters)
        try Task.checkCancellation()
        let migratedStates = await postProcessor.migratedReviewStates(
            previousSnapshots: previousSnapshots,
            previousReviewStates: previousReviewStates,
            newClusters: sortedClusters
        )
        let reviewData = await persistMigratedReviewData(migratedStates)
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

        let aggregates = await postProcessor.scanAggregates(
            clusters: sortedClusters,
            categories: refreshedCategories
        )
        let summary = ScanSummary(
            clusterCount: sortedClusters.count,
            cleanupCategoryCandidateCount: aggregates.categoryCandidateCount,
            estimatedSavingsBytes: aggregates.estimatedSavingsBytes,
            completedAt: completedAt
        )
        lastScanSummary = summary
        lastCompletedScanDate = summary.completedAt
        await progressRelay.submit(ScanProgressStages.completed, force: true)
        return summary
    }

    func publishScanProgress(_ progress: Double, scanID: UUID) {
        guard activeScan?.id == scanID,
              case .scanning(let current, let purpose) = scanOperation else {
            return
        }
        let next = max(current, min(max(progress, 0), 1))
        scanOperation = .scanning(progress: next, purpose: purpose)
    }

    func persistMigratedReviewData(
        _ result: ClusterReviewResurfacingResult
    ) async -> (
        states: [UUID: ClusterReviewState],
        resurfacingStates: [UUID: ClusterResurfacingState]
    ) {
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
        let states = await loadReviewStates()
        return await makeReviewData(for: clusters, reviewStates: states)
    }

    func loadReviewStates() async -> [UUID: ClusterReviewState] {
        do {
            return try await reviewRepository.loadAllReviewStates()
        } catch {
            return [:]
        }
    }

    func makeReviewData(
        for clusters: [PhotoCluster],
        reviewStates states: [UUID: ClusterReviewState]
    ) async -> (
        states: [UUID: ClusterReviewState],
        resurfacingStates: [UUID: ClusterResurfacingState],
        session: CleanupSession?
    ) {
        let resurfacingStates = await postProcessor.resurfacingStates(
            for: clusters,
            reviewStates: states
        )
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
        categorySnapshots: [CleanupCategoryKind: CleanupCategorySnapshot]?,
        scanMetadata: ScanMetadataSnapshot?
    ) async {
        do {
            try await repository.saveClusters(clusters)
        } catch {
            AppLog.storage.error("Failed to restore clusters after scan failure: \(error.localizedDescription)")
        }

        // The baseline may already have advanced before the failure; leaving it
        // there would pair a new scan date with the previous scan's clusters.
        do {
            try await repository.updateScanMetadata(scanMetadata)
        } catch {
            AppLog.storage.error("Failed to restore scan metadata after scan failure: \(error.localizedDescription)")
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

    func canCommitCachedLoad(_ expectedGeneration: Int) -> Bool {
        scanMutationGeneration == expectedGeneration && scanTask == nil
    }

    func publish(_ content: CleanupWorkspaceContent) {
        lastGoodContent = content
        refreshDerivedContentSnapshots()
        contentState = content.hasCompletedScanBaseline ? .content(content) : .neverScanned
    }

    /// Must be called at every site that replaces `lastGoodContent`.
    func refreshDerivedContentSnapshots() {
        let content = lastGoodContent
        clusterIdentityKey = content.clusters.map(\.id)
        sessionProgressSnapshot = cleanupManager.progress(
            for: content.clusters,
            reviewStates: content.reviewStates,
            activeSession: content.activeSession
        )
        cleanupEntryClusterSnapshot = cleanupManager.nextClusterToReview(
            from: content.clusters,
            reviewStates: content.reviewStates
        )
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

private actor ScanPostProcessor {
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

    func scanAggregates(
        clusters: [PhotoCluster],
        categories: [CleanupCategorySummary]
    ) -> (categoryCandidateCount: Int, estimatedSavingsBytes: Int64) {
        let categoryCandidateCount = categories.reduce(0) { $0 + max($1.assetCount, 0) }
        let clusterSavings = clusters.reduce(into: Int64(0)) { total, cluster in
            total += cluster.assets.reduce(into: Int64(0)) { $0 += $1.estimatedCleanupBytes }
        }
        let categorySavings = categories.reduce(into: Int64(0)) {
            $0 += $1.estimatedSavingsBytes
        }
        return (categoryCandidateCount, clusterSavings + categorySavings)
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
