import SwiftUI
import Photos
import Core
import Storage
import PhotoAnalysis
import Cleanup
import DesignSystem

public enum ScannerClusterSort: String, CaseIterable, Sendable {
    case newest
    case largestCleanupOpportunity
    case largestCluster
    case similarity
    case reviewStatus

    public var title: String {
        switch self {
        case .newest: appLocalized("Newest")
        case .largestCleanupOpportunity: appLocalized("Most space to save")
        case .largestCluster: appLocalized("Largest cluster")
        case .similarity: appLocalized("Highest similarity")
        case .reviewStatus: appLocalized("Review status")
        }
    }
}

public enum ScannerReviewFilter: String, CaseIterable, Sendable {
    case all
    case needsReview
    case inReview
    case reviewed

    public var title: String {
        switch self {
        case .all: appLocalized("All review states")
        case .needsReview: appLocalized("Needs review")
        case .inReview: appLocalized("In review")
        case .reviewed: appLocalized("Reviewed")
        }
    }
}

public enum ScannerMinimumClusterSize: Int, CaseIterable, Sendable {
    case any = 0
    case two = 2
    case three = 3
    case five = 5
    case ten = 10
    case twenty = 20

    public var title: String {
        switch self {
        case .any: appLocalized("Any size")
        case .two: appLocalized("2+ photos")
        case .three: appLocalized("3+ photos")
        case .five: appLocalized("5+ photos")
        case .ten: appLocalized("10+ photos")
        case .twenty: appLocalized("20+ photos")
        }
    }
}

public struct ScannerClusterControls: Equatable, Sendable {
    public var sort: ScannerClusterSort = .newest
    public var reviewFilter: ScannerReviewFilter = .all
    public var minimumClusterSize: ScannerMinimumClusterSize = .any
    public var favoritesOnly = false

    public var isDefault: Bool {
        self == Self()
    }

    public init() {}
}

public struct PostScanPremiumOffer: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let similarClusterCount: Int
    public let cleanupCategoryCandidateCount: Int
    public let estimatedSavingsBytes: Int64

    public init(
        id: UUID = UUID(),
        similarClusterCount: Int,
        cleanupCategoryCandidateCount: Int,
        estimatedSavingsBytes: Int64
    ) {
        self.id = id
        self.similarClusterCount = similarClusterCount
        self.cleanupCategoryCandidateCount = cleanupCategoryCandidateCount
        self.estimatedSavingsBytes = estimatedSavingsBytes
    }
}

@MainActor
@Observable
public final class ScannerViewModel {
    public enum State: Equatable {
        case idle
        case scanning(progress: Double)
        case results([PhotoCluster])
        case error(String)
    }

    public enum CleanupRefreshState: Equatable {
        case refreshing(CleanupCompletionRecord)
        case success(CleanupCompletionRecord)
        case failed(CleanupCompletionRecord, message: String)
    }

    private enum ScanPurpose {
        case userInitiated
        case postCleanupReconciliation

        var showsProgress: Bool {
            self == .userInitiated
        }

        var consumesFreeScanAllowance: Bool {
            self == .userInitiated
        }
    }
    
    public var state: State = .idle
    public var gridColumns: Int
    public private(set) var shouldShowRescanPrompt = false
    public private(set) var reviewStates: [UUID: ClusterReviewState] = [:]
    public private(set) var resurfacingStates: [UUID: ClusterResurfacingState] = [:]
    public private(set) var activeCleanupSession: CleanupSession?
    public private(set) var cleanupRefreshState: CleanupRefreshState?
    public private(set) var cleanupCategories: [CleanupCategorySummary] = []
    public private(set) var cleanupInsights: CleanupInsights = .empty
    public private(set) var pendingPostScanPremiumOffer: PostScanPremiumOffer?

    public var isCleanupRefreshInProgress: Bool {
        isCleanupRefreshInFlight
    }
    
    private let analysisService: PhotoAnalysisService
    private let repository: PhotoClusterRepository
    private let reviewRepository: ClusterReviewStateRepository
    private let cleanupCategoryRepository: CleanupCategorySnapshotRepository
    private let cleanupSessionRepository: CleanupSessionRepository
    private let cleanupManager: any CleanupSessionManaging
    private let cleanupInsightsProvider: any CleanupInsightsProviding
    let premiumAccess: any PremiumAccessControlling
    private let scanUsageRepository: any ScanUsageRepository
    private let premiumPromptHistoryRepository: any PremiumPromptHistoryRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let cleanupRefreshAutoDismissDelay: Duration
    private var cleanupRefreshDismissTask: Task<Void, Never>?
    private var userInitiatedScanOperation: (
        id: UUID,
        task: Task<PremiumAccessDecision, Never>
    )?
    private var scanUsageMigrationOperation: (
        id: UUID,
        task: Task<MonthlyScanUsage, Never>
    )?
    private var scanMutationGeneration = 0
    private var isUserInitiatedScanExecutionInFlight = false
    private var isCleanupRefreshInFlight = false
    private var activeCleanupRefreshRecord: CleanupCompletionRecord?
    private var queuedCleanupRefreshRecord: CleanupCompletionRecord?
    let cleanupService: any PhotoCleanupService
    let cleanupHistoryRepository: CleanupHistoryRepository
    public var sensitivity: SensitivityLevel
    public var clusterControls = ScannerClusterControls()
    public private(set) var monthlyScanUsage: MonthlyScanUsage?

    public var remainingFreeScans: Int {
        monthlyScanUsage?.remainingFreeScans ?? PremiumAccessPolicy.monthlyFreeScanLimit
    }

    public var nextFreeScanResetDate: Date? {
        monthlyScanUsage?.nextResetDate
    }

    public var hasUnlimitedScanAccess: Bool {
        premiumAccess.access(to: .unlimitedScans).isAllowed
    }
    
    public init(
        gridColumns: Int = 3,
        sensitivity: SensitivityLevel = .medium,
        analysisService: PhotoAnalysisService? = nil,
        repository: PhotoClusterRepository = CoreDataPhotoClusterRepository(),
        reviewRepository: ClusterReviewStateRepository = FileClusterReviewStateRepository(),
        cleanupCategoryRepository: CleanupCategorySnapshotRepository = FileCleanupCategorySnapshotRepository(),
        cleanupSessionRepository: CleanupSessionRepository = FileCleanupSessionRepository(),
        cleanupService: any PhotoCleanupService = PhotoKitCleanupService(),
        cleanupHistoryRepository: CleanupHistoryRepository = FileCleanupHistoryRepository(),
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        scanUsageRepository: any ScanUsageRepository = UserDefaultsScanUsageRepository(),
        premiumPromptHistoryRepository: any PremiumPromptHistoryRepository = UserDefaultsPremiumPromptHistoryRepository(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = Date.init,
        cleanupManager: (any CleanupSessionManaging)? = nil,
        cleanupInsightsProvider: (any CleanupInsightsProviding)? = nil,
        cleanupRefreshAutoDismissDelay: Duration = .seconds(5)
    ) {
        self.gridColumns = gridColumns
        self.sensitivity = sensitivity
        self.repository = repository
        self.reviewRepository = reviewRepository
        self.cleanupCategoryRepository = cleanupCategoryRepository
        self.cleanupSessionRepository = cleanupSessionRepository
        self.cleanupService = cleanupService
        self.cleanupHistoryRepository = cleanupHistoryRepository
        self.premiumAccess = premiumAccess
        self.scanUsageRepository = scanUsageRepository
        self.premiumPromptHistoryRepository = premiumPromptHistoryRepository
        self.calendar = calendar
        self.now = now
        self.cleanupManager = cleanupManager ?? CleanupSessionManager(repository: cleanupSessionRepository)
        self.cleanupInsightsProvider = cleanupInsightsProvider
            ?? CleanupInsightsService(repository: cleanupHistoryRepository)
        self.cleanupRefreshAutoDismissDelay = cleanupRefreshAutoDismissDelay
        
        if let analysisService {
            self.analysisService = analysisService
        } else if let featurePrintRepository = repository as? PhotoFeaturePrintRepository {
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
    
    public func loadCachedResults() async {
        let expectedScanGeneration = scanMutationGeneration
        let cachedInsights = await fetchCleanupInsights()
        let currentUsage = await resolveMonthlyScanUsage(at: now())

        if canCommitCachedResults(for: expectedScanGeneration) {
            cleanupInsights = cachedInsights
            monthlyScanUsage = currentUsage
        }

        do {
            let clusters = try await repository.loadClusters()
            let cachedCategories = await fetchCleanupCategories()
            guard canCommitCachedResults(for: expectedScanGeneration) else { return }

            cleanupCategories = cachedCategories
            if !clusters.isEmpty {
                let sorted = canonicalSortedClusters(from: clusters)
                if case .results(let existing) = state, existing == sorted {
                    return
                }
                AppLog.ui.debug("\(AppLog.tag(.cache, "Loaded cached clusters: \(sorted.count)"))")
                state = .results(sorted)
                await loadReviewStates(
                    clusters: sorted,
                    expectedScanGeneration: expectedScanGeneration
                )
            } else {
                let session = await cleanupManager.syncSession(for: [], reviewStates: [:])
                guard canCommitCachedResults(for: expectedScanGeneration) else { return }

                shouldShowRescanPrompt = false
                reviewStates = [:]
                resurfacingStates = [:]
                activeCleanupSession = session
            }
        } catch {
            AppLog.ui.error("\(AppLog.tag(.error, "Failed to load cached results: \(error.localizedDescription)"))")
        }
    }
    
    @discardableResult
    public func startScanning() async -> PremiumAccessDecision {
        if let operation = userInitiatedScanOperation {
            return await operation.task.value
        }

        let operationID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return PremiumAccessDecision.requiresPremium }
            return await self.performUserInitiatedScan()
        }
        userInitiatedScanOperation = (operationID, task)

        let decision = await task.value
        if userInitiatedScanOperation?.id == operationID {
            userInitiatedScanOperation = nil
        }
        return decision
    }

    private func performUserInitiatedScan() async -> PremiumAccessDecision {
        let currentUsage = await resolveMonthlyScanUsage(at: now())
        monthlyScanUsage = currentUsage
        let decision = premiumAccess.access(
            to: .unlimitedScans,
            context: .scan(completedThisMonth: currentUsage.completedScanCount)
        )
        guard decision.isAllowed else { return decision }

        scanMutationGeneration &+= 1
        isUserInitiatedScanExecutionInFlight = true
        defer { isUserInitiatedScanExecutionInFlight = false }

        do {
            setCleanupRefreshState(nil)
            try await runScan(purpose: .userInitiated)
        } catch {
            AppLog.scan.error("\(AppLog.tag(.error, "Scan failed: \(error.localizedDescription)"))")
            state = .error(error.localizedDescription)
        }
        return .allowed
    }

    public func handleCleanupCompleted(_ record: CleanupCompletionRecord) async {
        guard !isCleanupRefreshInFlight else {
            if record != activeCleanupRefreshRecord {
                queuedCleanupRefreshRecord = record
            }
            return
        }

        scanMutationGeneration &+= 1
        isCleanupRefreshInFlight = true
        var nextRecord: CleanupCompletionRecord? = record

        while let currentRecord = nextRecord {
            activeCleanupRefreshRecord = currentRecord
            queuedCleanupRefreshRecord = nil
            await performCleanupRefresh(for: currentRecord)
            nextRecord = queuedCleanupRefreshRecord
        }

        activeCleanupRefreshRecord = nil
        isCleanupRefreshInFlight = false
    }

    private func performCleanupRefresh(for record: CleanupCompletionRecord) async {
        setCleanupRefreshState(.refreshing(record))

        do {
            try await runScan(purpose: .postCleanupReconciliation)
            await loadCleanupInsights()
            setCleanupRefreshState(.success(record))
        } catch {
            AppLog.scan.error(
                "\(AppLog.tag(.error, "Cleanup refresh failed: \(error.localizedDescription)"))"
            )
            await loadCleanupInsights()
            setCleanupRefreshState(.failed(
                record,
                message: appLocalized("The photos were deleted, but the library refresh failed. Run a new scan to refresh your results.")
            ))
        }
    }

    public func retryCleanupRefresh() async {
        guard case .failed(let record, _) = cleanupRefreshState else { return }
        await handleCleanupCompleted(record)
    }

    public func dismissCleanupRefreshState() {
        setCleanupRefreshState(nil)
    }
    
    public func checkForGalleryChanges() async -> Bool {
        let hasChanged = await repository.hasGalleryChanged()
        shouldShowRescanPrompt = hasChanged && !currentResultClusters.isEmpty
        return shouldShowRescanPrompt
    }

    public func loadReviewStates() async {
        await loadReviewStates(clusters: currentResultClusters)
    }

    public func loadReviewStates(clusters: [PhotoCluster]) async {
        await loadReviewStates(clusters: clusters, expectedScanGeneration: nil)
    }

    private func loadReviewStates(
        clusters: [PhotoCluster],
        expectedScanGeneration: Int?
    ) async {
        let loadedReviewStates: [UUID: ClusterReviewState]
        do {
            loadedReviewStates = try await reviewRepository.loadAllReviewStates()
        } catch {
            AppLog.ui.error("\(AppLog.tag(.error, "Failed to load review states: \(error.localizedDescription)"))")
            loadedReviewStates = [:]
        }

        let loadedResurfacingStates = Dictionary(
            uniqueKeysWithValues: clusters.map { cluster in
                (cluster.id, loadedReviewStates[cluster.id]?.resurfacingState ?? .unchanged)
            }
        )
        let loadedSession = await cleanupManager.syncSession(
            for: clusters,
            reviewStates: loadedReviewStates
        )

        if let expectedScanGeneration {
            guard canCommitCachedResults(for: expectedScanGeneration) else { return }
        }

        reviewStates = loadedReviewStates
        resurfacingStates = loadedResurfacingStates
        activeCleanupSession = loadedSession
    }

    public func reviewState(for clusterID: UUID) -> ClusterReviewState? {
        reviewStates[clusterID]
    }

    public func isCategoryLocked(_ kind: CleanupCategoryKind) -> Bool {
        !premiumAccess.access(to: kind.premiumFeature).isAllowed
    }

    public var isAdvancedFilteringLocked: Bool {
        !premiumAccess.access(to: .advancedFilters).isAllowed
    }

    var effectiveClusterControls: ScannerClusterControls {
        guard isAdvancedFilteringLocked else { return clusterControls }

        var controls = clusterControls
        controls.reviewFilter = .all
        controls.minimumClusterSize = .any
        controls.favoritesOnly = false
        return controls
    }

    public func loadAssets(for category: CleanupCategoryKind) async throws -> [PHAsset] {
        try await analysisService.loadAssets(for: category)
    }

    public func reviewStatus(for clusterID: UUID) -> ClusterReviewStatus {
        reviewStates[clusterID]?.status ?? .notReviewed
    }

    public func resurfacingState(for clusterID: UUID) -> ClusterResurfacingState? {
        let state = resurfacingStates[clusterID] ?? .unchanged
        return state == .unchanged ? nil : state
    }

    public func needsReviewClusters(from clusters: [PhotoCluster]) -> [PhotoCluster] {
        clusters.filter { reviewStatus(for: $0.id) == .needsReReview }
    }

    public func remainingClusters(from clusters: [PhotoCluster]) -> [PhotoCluster] {
        clusters.filter { reviewStatus(for: $0.id) != .needsReReview }
    }

    public func sessionProgress(for clusters: [PhotoCluster]) -> CleanupSessionProgress {
        cleanupManager.progress(
            for: clusters,
            reviewStates: reviewStates,
            activeSession: nil
        )
    }

    public func displayedSessionProgress(for clusters: [PhotoCluster]) -> CleanupSessionProgress {
        cleanupManager.progress(
            for: clusters,
            reviewStates: reviewStates,
            activeSession: activeCleanupSession
        )
    }

    public func cleanupEntryCluster(from clusters: [PhotoCluster]) -> PhotoCluster? {
        cleanupManager.nextClusterToReview(from: clusters, reviewStates: reviewStates)
    }

    public func sortedClusters(from clusters: [PhotoCluster]) -> [PhotoCluster] {
        filteredAndSortedClusters(from: clusters, controls: effectiveClusterControls)
    }

    func canonicalSortedClusters(from clusters: [PhotoCluster]) -> [PhotoCluster] {
        clusters.sorted(by: defaultClusterSort)
    }

    public func filteredAndSortedClusters(
        from clusters: [PhotoCluster],
        controls: ScannerClusterControls
    ) -> [PhotoCluster] {
        let filtered = clusters.filter { cluster in
            guard cluster.count >= controls.minimumClusterSize.rawValue else { return false }
            if controls.favoritesOnly && !cluster.assets.contains(where: { $0.isFavorite }) { return false }
            switch controls.reviewFilter {
            case .all: return true
            case .needsReview: return reviewStatus(for: cluster.id) == .needsReReview
            case .inReview: return reviewStatus(for: cluster.id) == .inReview
            case .reviewed: return reviewStatus(for: cluster.id) == .reviewed
            }
        }

        return filtered.sorted { lhs, rhs in
            let primary: ComparisonResult
            switch controls.sort {
            case .newest:
                primary = compare(lhs.createdAt, rhs.createdAt, descending: true)
            case .largestCleanupOpportunity:
                primary = compare(cleanupBytes(for: lhs), cleanupBytes(for: rhs), descending: true)
            case .largestCluster:
                primary = compare(lhs.count, rhs.count, descending: true)
            case .similarity:
                primary = compare(lhs.averageSimilarity, rhs.averageSimilarity, descending: true)
            case .reviewStatus:
                primary = compare(reviewRank(for: lhs), reviewRank(for: rhs), descending: true)
            }
            guard primary == .orderedSame else { return primary == .orderedAscending }
            return defaultClusterSort(lhs, rhs)
        }
    }

    public func resetClusterControls() {
        clusterControls = ScannerClusterControls()
    }

    public func consumePostScanPremiumOffer() {
        pendingPostScanPremiumOffer = nil
    }
}

private extension ScannerViewModel {
    func cleanupBytes(for cluster: PhotoCluster) -> Int64 {
        cluster.assets.reduce(0) { $0 + $1.estimatedCleanupBytes }
    }

    func reviewRank(for cluster: PhotoCluster) -> Int {
        switch reviewStatus(for: cluster.id) {
        case .needsReReview: 3
        case .inReview: 2
        case .notReviewed: 1
        case .reviewed: 0
        }
    }

    func defaultClusterSort(_ lhs: PhotoCluster, _ rhs: PhotoCluster) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        if lhs.averageSimilarity != rhs.averageSimilarity { return lhs.averageSimilarity > rhs.averageSimilarity }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func compare<T: Comparable>(_ lhs: T, _ rhs: T, descending: Bool) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        let lhsBefore = descending ? lhs > rhs : lhs < rhs
        return lhsBefore ? .orderedAscending : .orderedDescending
    }

    func setCleanupRefreshState(_ newState: CleanupRefreshState?) {
        cleanupRefreshDismissTask?.cancel()
        cleanupRefreshDismissTask = nil
        cleanupRefreshState = newState

        guard case .success(let record)? = newState else {
            return
        }

        let delay = cleanupRefreshAutoDismissDelay
        guard delay > .zero else {
            cleanupRefreshState = nil
            return
        }
        cleanupRefreshDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            self?.dismissCleanupRefreshStateIfMatching(record)
        }
    }

    func dismissCleanupRefreshStateIfMatching(_ record: CleanupCompletionRecord) {
        guard cleanupRefreshState == .success(record) else {
            return
        }
        cleanupRefreshState = nil
        cleanupRefreshDismissTask = nil
    }

    func fetchCleanupInsights() async -> CleanupInsights {
        do {
            return try await cleanupInsightsProvider.loadInsights()
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to load cleanup insights: \(error.localizedDescription)"))"
            )
            return .empty
        }
    }

    func loadCleanupInsights() async {
        cleanupInsights = await fetchCleanupInsights()
    }

    func fetchCleanupCategories() async -> [CleanupCategorySummary] {
        do {
            let snapshots = try await cleanupCategoryRepository.loadAllSnapshots()
            return CleanupCategoryKind.allCases.compactMap { snapshots[$0]?.summary }
        } catch {
            AppLog.photoKit.error(
                "\(AppLog.tag(.error, "Failed to load cleanup categories: \(error.localizedDescription)"))"
            )
            return []
        }
    }

    func loadCleanupCategories() async {
        cleanupCategories = await fetchCleanupCategories()
    }

    private func runScan(purpose: ScanPurpose) async throws {
        AppLog.scan.info("\(AppLog.tag(.start, "Scan started"))")
        if purpose.showsProgress {
            state = .scanning(progress: 0.0)
        }

        let previousSnapshots = try await repository.loadClusterSnapshots()
        let previousReviewStates = try await loadAllReviewStates()
        let clusters = try await analysisService.analyzePhotoLibrary(
            sensitivity: sensitivity.threshold
        ) { progress in
            guard purpose.showsProgress else { return }
            Task { @MainActor in
                self.state = .scanning(progress: progress)
            }
        }

        try await repository.saveClusters(clusters)
        try await repository.updateLastScanDate(Date())

        let sorted = canonicalSortedClusters(from: clusters)

        if previousSnapshots.isEmpty {
            reviewStates = [:]
            resurfacingStates = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, .unchanged) })
            do {
                try await persistReviewStates([:])
            } catch {
                AppLog.storage.error(
                    "\(AppLog.tag(.error, "Failed to clear stale review states: \(error.localizedDescription)"))"
                )
            }
        } else {
            let resurfacing = ClusterReviewStateResurfacer.resurface(
                previousSnapshots: previousSnapshots,
                newClusters: sorted,
                existingReviewStates: previousReviewStates
            )
            reviewStates = resurfacing.migratedReviewStates
            resurfacingStates = resurfacing.resurfacingStates
            do {
                try await persistReviewStates(reviewStates)
            } catch {
                AppLog.storage.error(
                    "\(AppLog.tag(.error, "Failed to persist migrated review states: \(error.localizedDescription)"))"
                )
            }
        }

        activeCleanupSession = await cleanupManager.syncSession(for: sorted, reviewStates: reviewStates)
        AppLog.scan.info("\(AppLog.tag(.finish, "Scan finished with clusters: \(sorted.count)"))")
        shouldShowRescanPrompt = false
        do {
            cleanupCategories = try await analysisService.refreshCleanupCategories()
        } catch {
            AppLog.photoKit.error(
                "\(AppLog.tag(.error, "Failed to refresh cleanup categories: \(error.localizedDescription)"))"
            )
            cleanupCategories = []
        }
        state = .results(sorted)
        if purpose.consumesFreeScanAllowance {
            monthlyScanUsage = await scanUsageRepository.recordCompletedScan(at: now())
            await publishPostScanPremiumOfferIfEligible(
                clusters: sorted,
                categories: cleanupCategories
            )
        }
    }

    func publishPostScanPremiumOfferIfEligible(
        clusters: [PhotoCluster],
        categories: [CleanupCategorySummary]
    ) async {
        guard !premiumAccess.entitlementState.isPremium else { return }

        let categoryCandidateCount = categories.reduce(0) { $0 + $1.assetCount }
        guard !clusters.isEmpty || categoryCandidateCount > 0 else { return }
        guard await premiumPromptHistoryRepository.claimPostFirstUsefulScanPrompt() else { return }

        let clusterSavings = clusters.reduce(into: Int64(0)) { total, cluster in
            total += cluster.assets.reduce(0) { $0 + $1.estimatedCleanupBytes }
        }
        let categorySavings = categories.reduce(into: Int64(0)) { total, category in
            total += category.estimatedSavingsBytes
        }
        pendingPostScanPremiumOffer = PostScanPremiumOffer(
            similarClusterCount: clusters.count,
            cleanupCategoryCandidateCount: categoryCandidateCount,
            estimatedSavingsBytes: clusterSavings + categorySavings
        )
    }

    private func resolveMonthlyScanUsage(at date: Date) async -> MonthlyScanUsage {
        if let storedUsage = await scanUsageRepository.loadMonthlyUsage(at: date) {
            return storedUsage
        }

        let migratedUsage = await migrateMonthlyScanUsageIfNeeded(at: date)
        if let canonicalUsage = await scanUsageRepository.loadMonthlyUsage(at: date) {
            return canonicalUsage
        }
        return migratedUsage
    }

    private func migrateMonthlyScanUsageIfNeeded(at date: Date) async -> MonthlyScanUsage {
        if let operation = scanUsageMigrationOperation {
            _ = await operation.task.value
            if let canonicalUsage = await scanUsageRepository.loadMonthlyUsage(at: date) {
                return canonicalUsage
            }
            return await makeMigratedMonthlyScanUsage(at: date)
        }

        let operationID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return MonthlyScanUsage(
                    periodStart: date,
                    nextResetDate: date,
                    completedScanCount: 0
                )
            }
            let migratedUsage = await self.makeMigratedMonthlyScanUsage(at: date)
            await self.scanUsageRepository.initializeMonthlyUsage(migratedUsage)
            return migratedUsage
        }
        scanUsageMigrationOperation = (operationID, task)

        let migratedUsage = await task.value
        if scanUsageMigrationOperation?.id == operationID {
            scanUsageMigrationOperation = nil
        }
        return migratedUsage
    }

    private func makeMigratedMonthlyScanUsage(at currentDate: Date) async -> MonthlyScanUsage {
        let lastScanDate = await repository.getLastScanDate()
        let migratedCount = lastScanDate.map {
            calendar.isDate($0, equalTo: currentDate, toGranularity: .month) ? 1 : 0
        } ?? 0
        let components = calendar.dateComponents([.year, .month], from: currentDate)
        let periodStart = calendar.date(from: components) ?? currentDate
        let nextResetDate = calendar.date(byAdding: .month, value: 1, to: periodStart) ?? currentDate
        return MonthlyScanUsage(
            periodStart: periodStart,
            nextResetDate: nextResetDate,
            completedScanCount: migratedCount
        )
    }

    private func canCommitCachedResults(for expectedScanGeneration: Int) -> Bool {
        scanMutationGeneration == expectedScanGeneration
            && !isUserInitiatedScanExecutionInFlight
            && !isCleanupRefreshInFlight
    }

    func loadAllReviewStates() async throws -> [UUID: ClusterReviewState] {
        try await reviewRepository.loadAllReviewStates()
    }

    func persistReviewStates(_ states: [UUID: ClusterReviewState]) async throws {
        try await reviewRepository.deleteAllReviewStates()
        for state in states.values {
            try await reviewRepository.saveReviewState(state)
        }
    }

    var currentResultClusters: [PhotoCluster] {
        if case .results(let clusters) = state {
            return clusters
        }
        return []
    }
}
