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
    public internal(set) var scanOperation: ScanOperationState = .idle
    public internal(set) var reconciliationState: CleanupReconciliationState?
    public internal(set) var lastScanSummary: ScanSummary?
    public internal(set) var lastCompletedScanDate: Date?
    /// The whole library's size as the last saved scan summed it — the widget
    /// ring's denominator. `nil` until a scan has measured it, never 0.
    public internal(set) var libraryTotalBytes: Int64?
    /// What the store is known to hold. A failed write leaves it behind
    /// `libraryTotalBytes`, so the next scan retries an unchanged total.
    var persistedLibraryTotalBytes: Int64?
    public let cleanupService: any PhotoCleanupService
    public let cleanupHistoryRepository: any CleanupHistoryRepository
    /// Best Shot quality scoring, cached in Core Data so reopening a cluster
    /// does not decode its photos again.
    public let qualityAnalyzer: any PhotoQualityAnalyzing
    /// Non-destructive Best Shot enhancement, backed by PhotoKit content
    /// editing; it shares the score cache so our own edit is never re-scored.
    public let enhancementService: any PhotoEnhancementService
    /// On-device counters that say how often the ranking gets replaced; the
    /// calibration signal, with nothing leaving the device.
    public let bestShotOverrideMetrics: any BestShotOverrideMetricsRepository
    /// Applies the device's personalized Best Shot weights on top of the
    /// global scoring config, and records every override that replaces our
    /// recommendation so the fit keeps improving.
    public let bestShotPersonalizedConfigProvider: BestShotPersonalizedScoringConfigProvider

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
    /// The reclaimable figure for the current content. Every surface that shows
    /// "reclaimable" reads this; it is refreshed once per published content, not
    /// on every read, because resolving each cluster's keeper is not free.
    public private(set) var reclaimableEstimate: ReclaimableEstimate = .zero

    let analysisService: any PhotoAnalysisService
    let repository: any PhotoClusterRepository
    let reviewRepository: any ClusterReviewStateRepository
    let cleanupCategoryRepository: any CleanupCategorySnapshotRepository
    let cleanupManager: any CleanupSessionManaging
    let cleanupInsightsProvider: any CleanupInsightsProviding
    let now: @Sendable () -> Date
    /// Re-measures persisted category sums written with the pixel heuristic.
    let assetBytesByIdentifier: @Sendable ([String]) -> [String: Int64]
    let assetByteSizeRepository: any AssetByteSizeRepository
    /// `AssetByteSize.generation` at the last load or save of the size store.
    var persistedByteSizeGeneration: Int?
    let postProcessor = ScanPostProcessor()

    private(set) var lastGoodContent = CleanupWorkspaceContent.empty

    /// Derived from `lastGoodContent` and refreshed only when it is replaced.
    ///
    /// `CleanupView` reads all three during `body`, where an O(clusters) pass
    /// would re-run on every unrelated state flip — opening the filter sheet,
    /// dismissing an alert. Their inputs live entirely in `lastGoodContent`, so
    /// recomputing where it is published is equivalent and happens far less
    /// often. They stay observable stored properties, so views still update.
    private(set) var sessionProgressSnapshot: CleanupSessionProgress = .empty
    private(set) var cleanupEntryClusterSnapshot: PhotoCluster?
    public private(set) var clusterIdentityKey: [UUID] = []
    var scanMutationGeneration = 0
    private var cachedContentLoadTask: Task<Void, Never>?
    var activeScan: (id: UUID, sensitivity: SensitivityLevel, purpose: ScanOperationPurpose)?
    var scanTask: Task<ScanSummary, Error>?
    var progressRelay: ScanProgressRelay?
    private var reconciliationTask: Task<Void, Never>?
    var activeReconciliation: (record: CleanupCompletionRecord, sensitivity: SensitivityLevel)?
    var queuedReconciliation: (record: CleanupCompletionRecord, sensitivity: SensitivityLevel)?

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
        enhancementService: any PhotoEnhancementService = PhotoKitEnhancementService(
            qualityScoreRepository: CoreDataPhotoQualityScoreRepository()
        ),
        bestShotOverrideMetrics: any BestShotOverrideMetricsRepository =
            UserDefaultsBestShotOverrideMetricsRepository(),
        bestShotPersonalizedConfigProvider: BestShotPersonalizedScoringConfigProvider =
            BestShotPersonalizedScoringConfigProvider(
                repository: UserDefaultsBestShotPersonalizationRepository()
            ),
        cleanupManager: (any CleanupSessionManaging)? = nil,
        assetByteSizeRepository: any AssetByteSizeRepository = FileAssetByteSizeRepository(),
        assetBytesByIdentifier: @escaping @Sendable ([String]) -> [String: Int64] =
            AssetByteSize.bytes(forLocalIdentifiers:),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.reviewRepository = reviewRepository
        self.cleanupCategoryRepository = cleanupCategoryRepository
        self.cleanupService = cleanupService
        self.cleanupHistoryRepository = cleanupHistoryRepository
        self.qualityAnalyzer = qualityAnalyzer
        self.enhancementService = enhancementService
        self.bestShotOverrideMetrics = bestShotOverrideMetrics
        self.bestShotPersonalizedConfigProvider = bestShotPersonalizedConfigProvider
        self.cleanupManager = cleanupManager ?? CleanupSessionManager(repository: cleanupSessionRepository)
        self.cleanupInsightsProvider = CleanupInsightsService(repository: self.cleanupHistoryRepository)
        self.assetBytesByIdentifier = assetBytesByIdentifier
        self.assetByteSizeRepository = assetByteSizeRepository
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
            // Seeded before anything is measured: the legacy re-measurements below
            // must count as newer than the store, or a load that measures nothing
            // else afterwards would never write them to disk.
            await seedByteSizesIfNeeded()
            let loadedClusters = try await repository.loadClusters()
            let categorySnapshots = await fetchCleanupCategorySnapshots(
                persistingRemeasurementsFor: expectedGeneration
            )
            let reviewData = await makeReviewData(
                for: loadedClusters,
                persistingRemeasurementsFor: expectedGeneration
            )
            let storedLibraryTotalBytes = baselineDate == nil
                ? nil
                : await assetByteSizeRepository.loadLibraryTotalBytes()

            guard canCommitCachedLoad(expectedGeneration) else { return }

            let sortedClusters = await postProcessor.canonicalSortedClusters(loadedClusters)
            // Publishing reads bytes for every cluster asset on the main actor. Sizes
            // measured by an earlier launch come from disk, so PhotoKit is asked only
            // about photos that are new or changed since.
            await postProcessor.prewarmByteSizes(for: sortedClusters)
            let content = CleanupWorkspaceContent(
                clusters: sortedClusters,
                categories: categorySnapshots.map(\.summary),
                reviewStates: reviewData.states,
                resurfacingStates: reviewData.resurfacingStates,
                activeSession: reviewData.session,
                insights: insights,
                hasCompletedScanBaseline: baselineDate != nil,
                shouldShowRescanPrompt: false,
                categorySnapshots: categorySnapshots
            )
            // A scan may have finished during the awaits above; everything below
            // publishes together, with no suspension point in between.
            guard canCommitCachedLoad(expectedGeneration) else { return }
            lastGoodContent = content
            refreshDerivedContentSnapshots()
            lastCompletedScanDate = baselineDate
            libraryTotalBytes = storedLibraryTotalBytes
            persistedLibraryTotalBytes = storedLibraryTotalBytes
            contentState = baselineDate == nil ? .neverScanned : .content(content)
            await persistByteSizesIfNeeded(for: content)
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
            reviewStates: reviewStates,
            persistingRemeasurementsFor: expectedGeneration
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

        // `self` outlives the deletion — the workspace is never rebuilt after
        // a full delete — so the provider's in-memory cache must be cleared
        // explicitly here or a stale personalized config would survive the
        // repository wipe underneath it.
        await bestShotPersonalizedConfigProvider.reset()

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
        libraryTotalBytes = nil
        persistedLibraryTotalBytes = nil
        try? await assetByteSizeRepository.saveLibraryTotalBytes(nil)
    }
}

extension CleanupWorkspaceModel {
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
        // Observation fires on every write, so an unchanged figure is not rewritten:
        // a review-state or session change that leaves the estimate alone must not
        // re-derive the scanner summary or republish the widget snapshot.
        let estimate = content.reclaimableEstimate()
        if reclaimableEstimate != estimate {
            reclaimableEstimate = estimate
            // A keeper change moves the estimate without a scan; the scanner card and
            // the widget read the summary first, so it must carry the same figure.
            if let summary = lastScanSummary, summary.estimatedSavingsBytes != estimate.totalBytes {
                lastScanSummary = ScanSummary(
                    clusterCount: summary.clusterCount,
                    cleanupCategoryCandidateCount: summary.cleanupCategoryCandidateCount,
                    estimatedSavingsBytes: estimate.totalBytes,
                    completedAt: summary.completedAt
                )
            }
        }
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
            shouldShowRescanPrompt: shouldShowRescanPrompt ?? content.shouldShowRescanPrompt,
            categorySnapshots: content.categorySnapshots
        )
    }
}
