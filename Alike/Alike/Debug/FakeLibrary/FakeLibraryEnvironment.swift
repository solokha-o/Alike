#if DEBUG
import CleanupWorkspace
import Core
import Foundation
import os
import PhotoAnalysis
import Photos

/// The dependencies of one fake library scenario, built from the public Core mocks.
///
/// Every store is in memory: a fake session never writes Core Data, the JSON files
/// in Application Support, or the widget snapshot, and it never deletes a photo.
final class FakeLibraryEnvironment {
    /// The scenario named by the launch arguments, or `nil` for the real library.
    static let current: FakeLibraryEnvironment? = {
        guard let scenario = FakeLibraryScenario.fromLaunchArguments() else {
            if let rawValue = UserDefaults.standard.string(forKey: FakeLibraryScenario.launchArgumentKey) {
                AppLog.ui.error("Fake library: unknown scenario \(rawValue), the real library is used")
            }
            return nil
        }
        let environment = FakeLibraryEnvironment(
            scenario: scenario,
            isPremium: FakeLibraryScenario.isPremiumFromLaunchArguments()
        )
        environment.applyPremiumOverrides()
        AppLog.ui.info("Fake library: \(scenario.rawValue), premium \(environment.isPremium)")
        return environment
    }()

    /// A fixed date, so every capture shows the same "last scan" text.
    nonisolated static let referenceDate = Date(timeIntervalSince1970: 1_794_000_000)

    let scenario: FakeLibraryScenario
    let isPremium: Bool
    /// `false` in tests: an access prompt there has no one to answer it.
    let requestsPhotoAccess: Bool

    let permissionManager: MockPhotoPermissionManager
    let repository = MockPhotoClusterRepository()
    let analysisService = MockPhotoAnalysisService()
    let reviewRepository = MockClusterReviewStateRepository()
    let categoryRepository = MockCleanupCategorySnapshotRepository()
    let sessionRepository = MockCleanupSessionRepository()
    let cleanupService = MockPhotoCleanupService()
    let historyRepository = MockCleanupHistoryRepository()
    let qualityAnalyzer = MockPhotoQualityAnalyzer()
    let assetByteSizeRepository = MockAssetByteSizeRepository()
    let reminderManager = MockCleanupReminderManager()
    let ratingPromptRepository = MockRatingPromptHistoryRepository()

    private(set) var clusters: [PhotoCluster] = []
    private(set) var categoryAssets: [PHAsset] = []
    private var preparation: Task<Void, Never>?

    init(scenario: FakeLibraryScenario, isPremium: Bool, requestsPhotoAccess: Bool = true) {
        self.scenario = scenario
        self.isPremium = isPremium
        self.requestsPhotoAccess = requestsPhotoAccess
        permissionManager = MockPhotoPermissionManager(
            authorizationStatus: scenario.hasPhotoAccess ? .authorized : .denied
        )
    }

    /// Forces every Premium debug override on or off for this process only.
    ///
    /// The argument domain wins over values a debug toggle saved earlier and is
    /// never written to disk, so `DebugPremiumAccessController` and the
    /// `@AppStorage` mirrors in `MainTabView` all read the same answer.
    func applyPremiumOverrides(to defaults: UserDefaults = .standard) {
        var domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        for feature in PremiumFeature.allCases {
            domain[feature.debugOverrideDefaultsKey] = isPremium
        }
        defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    /// Premium access for a screen built outside `MainTabView`, such as a capture test.
    var premiumAccess: MockPremiumAccessController {
        MockPremiumAccessController(unlockedFeatures: isPremium ? Set(PremiumFeature.allCases) : [])
    }

    /// Loads the photos and fills the mocks. Safe to call more than once.
    func prepare() async {
        if preparation == nil {
            preparation = Task { await load() }
        }
        await preparation?.value
    }

    /// A workspace that reads and writes only this environment's mocks.
    func makeWorkspace() -> CleanupWorkspaceModel {
        CleanupWorkspaceModel(
            analysisService: analysisService,
            repository: repository,
            reviewRepository: reviewRepository,
            cleanupCategoryRepository: categoryRepository,
            cleanupSessionRepository: sessionRepository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: historyRepository,
            qualityAnalyzer: qualityAnalyzer,
            enhancementService: PhotoKitEnhancementService(
                qualityScoreRepository: MockPhotoQualityScoreRepository()
            ),
            bestShotOverrideMetrics: MockBestShotOverrideMetricsRepository(),
            bestShotPersonalizedConfigProvider: BestShotPersonalizedScoringConfigProvider(
                repository: MockBestShotPersonalizationRepository()
            ),
            assetByteSizeRepository: assetByteSizeRepository,
            now: { FakeLibraryEnvironment.referenceDate }
        )
    }

    private func load() async {
        guard scenario.hasPhotoAccess else { return }
        let assets = await FakeLibraryPhotoStore.assets(
            minimumCount: scenario.requiredPhotoCount + scenario.categoryPhotoCount,
            requestsAccess: requestsPhotoAccess
        )
        clusters = Self.makeClusters(for: scenario, from: assets)
        categoryAssets = Array(assets.suffix(min(scenario.categoryPhotoCount, assets.count)))

        await repository.setLoadClustersResult(.success(clusters))
        await repository.setGetLastScanDateResult(Self.referenceDate)
        await repository.setLibraryFingerprint(token: Data([0xFA, 0x4E]), imageAssetCount: assets.count)
        await analysisService.setAnalyzePhotoLibraryResult(.success(clusters))
        await analysisService.setLoadAssetsResult(.success(categoryAssets))

        let snapshots = makeCategorySnapshots()
        await categoryRepository.setStoredSnapshots(snapshots)
        await analysisService.setSummarizeCleanupCategoriesResult(.success(
            CleanupCategoryKind.allCases.compactMap { kind in
                snapshots[kind].map {
                    CleanupCategorySummary(
                        kind: kind,
                        assetCount: $0.assetCount,
                        estimatedSavingsBytes: $0.estimatedSavingsBytes
                    )
                }
            }
        ))

        if scenario == .afterCleanup {
            await seedFinishedReviews()
        }
    }

    /// Groups in scenario order. IDs are fixed so review states can point at them.
    static func makeClusters(for scenario: FakeLibraryScenario, from assets: [PHAsset]) -> [PhotoCluster] {
        var clusters: [PhotoCluster] = []
        var offset = 0
        for (index, size) in scenario.clusterSizes.enumerated() {
            let start = scenario == .manyClusters ? index : offset
            let end = start + size
            guard end <= assets.count else { break }
            clusters.append(PhotoCluster(
                id: clusterID(index),
                assets: Array(assets[start ..< end]),
                createdAt: referenceDate,
                averageSimilarity: 0.9 - Float(index % 5) * 0.02
            ))
            offset = end
        }
        return clusters
    }

    static func clusterID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "FA4E0000-0000-4000-8000-%012d", index)) ?? UUID()
    }

    private func makeCategorySnapshots() -> [CleanupCategoryKind: CleanupCategorySnapshot] {
        guard !categoryAssets.isEmpty else { return [:] }
        let half = categoryAssets.count / 2
        let groups: [(CleanupCategoryKind, ArraySlice<PHAsset>)] = [
            (.screenshots, categoryAssets[..<half]),
            (.blurredPhotos, categoryAssets[half...]),
        ]
        var snapshots: [CleanupCategoryKind: CleanupCategorySnapshot] = [:]
        for (kind, assets) in groups {
            snapshots[kind] = CleanupCategorySnapshot(
                kind: kind,
                localIdentifiers: assets.map(\.localIdentifier),
                assetCount: assets.count,
                estimatedSavingsBytes: Int64(assets.count) * 2_400_000,
                refreshedAt: Self.referenceDate
            )
        }
        return snapshots
    }

    /// Half of the groups reviewed and cleaned, with matching history and session.
    private func seedFinishedReviews() async {
        let reviewed = clusters.prefix(clusters.count / 2)
        var states: [UUID: ClusterReviewState] = [:]
        var history: [CleanupCompletionRecord] = []
        for (index, cluster) in reviewed.enumerated() {
            guard let keeper = cluster.assets.first else { continue }
            let removed = cluster.assets.dropFirst().map(\.localIdentifier)
            let savings = Int64(removed.count) * 2_400_000
            states[cluster.id] = ClusterReviewState(
                clusterID: cluster.id,
                bestShotLocalIdentifier: keeper.localIdentifier,
                selectedLocalIdentifiers: Set(removed),
                status: .reviewed,
                estimatedSavingsBytes: savings,
                updatedAt: Self.referenceDate
            )
            history.append(CleanupCompletionRecord(
                sourceClusterID: cluster.id,
                deletedCount: removed.count,
                estimatedSavingsBytes: savings,
                completedAt: Self.referenceDate.addingTimeInterval(Double(-index) * 86_400)
            ))
        }
        await reviewRepository.setStoredStates(states)
        await historyRepository.setEntries(history)
        await sessionRepository.setStoredSession(CleanupSession(
            createdAt: Self.referenceDate.addingTimeInterval(-3 * 86_400),
            updatedAt: Self.referenceDate,
            totalClusters: clusters.count,
            reviewedClusters: reviewed.count,
            estimatedSavingsBytes: history.reduce(0) { $0 + $1.estimatedSavingsBytes }
        ))
    }
}
#endif
