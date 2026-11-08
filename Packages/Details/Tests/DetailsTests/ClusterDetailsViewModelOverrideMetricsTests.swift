import Core
import Foundation
import Photos
import Testing
@testable import Details

@MainActor
struct ClusterDetailsViewModelOverrideMetricsTests: ClusterDetailsViewModelFixture {
    let repository = MockClusterReviewStateRepository()
    let cleanupService = MockPhotoCleanupService()
    let cleanupHistoryRepository = MockCleanupHistoryRepository()
    let clusterID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

    // MARK: - Anonymous override metrics

    @Test func testOpeningAClusterWithARecommendationCountsIt() async {
        let metrics = MockBestShotOverrideMetricsRepository()
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "sharp", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "blurred", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20)),
            ],
            qualityScores: [("sharp", 60), ("blurred", 20)],
            overrideMetrics: metrics
        )

        await viewModel.load()

        let recorded = await metrics.recordedRecommendations
        #expect(recorded == [.automatic])
    }

    @Test func testReplacingTheRecommendationIsCountedAsAnOverride() async {
        let metrics = MockBestShotOverrideMetricsRepository()
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "sharp", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "blurred", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20)),
            ],
            qualityScores: [("sharp", 60), ("blurred", 20)],
            overrideMetrics: metrics
        )
        await viewModel.load()

        viewModel.setBestShot("blurred")
        await waitForRecordedManualPicks(1, on: metrics)

        let picks = await metrics.recordedManualPicks
        #expect(picks == [.automatic])
        let stored = await metrics.metrics
        #expect(stored.manualOverrideCount == 1)
    }

    /// Switching between the user's own picks says nothing about the ranking.
    @Test func testSwitchingBetweenOwnPicksIsNotCountedTwice() async {
        let metrics = MockBestShotOverrideMetricsRepository()
        let viewModel = makeViewModel(
            snapshots: [
                snapshot(id: "a", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "b", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 20)),
                snapshot(id: "c", isFavorite: false, area: 1_000, createdAt: Date(timeIntervalSince1970: 30)),
            ],
            qualityScores: [("a", 60), ("b", 20), ("c", 25)],
            overrideMetrics: metrics
        )
        await viewModel.load()

        viewModel.setBestShot("b")
        await waitForRecordedManualPicks(1, on: metrics)
        viewModel.setBestShot("c")
        await Task.yield()

        let picks = await metrics.recordedManualPicks
        #expect(picks == [.automatic])
    }

    @Test func testAnUnresolvedClusterRecordsNeitherRecommendationNorOverride() async {
        let metrics = MockBestShotOverrideMetricsRepository()
        let viewModel = makeViewModel(
            snapshots: weakClusterSnapshots,
            qualityScores: [("a", 4), ("b", 3.6), ("c", 3.8)],
            overrideMetrics: metrics
        )
        await viewModel.load()

        viewModel.setBestShot("b")
        await waitForRecordedManualPicks(1, on: metrics)

        let recommendations = await metrics.recordedRecommendations
        let picks = await metrics.recordedManualPicks
        let stored = await metrics.metrics
        #expect(recommendations.isEmpty)
        #expect(picks == [.unresolved])
        #expect(stored.manualOverrideCount == 0)
        #expect(stored.unresolvedManualPickCount == 1)
    }

    /// The screen shows a Best Shot before scoring finishes, so an override can
    /// arrive first. Both sides of the rate have to survive that.
    @Test func testAnOverrideBeforeScoringFinishesStillCountsBothSides() async {
        let metrics = MockBestShotOverrideMetricsRepository()
        let analyzer = StallingPhotoQualityAnalyzer()
        let viewModel = ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: repository,
            cleanupService: cleanupService,
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: analyzer,
            overrideMetrics: metrics,
            assetSnapshots: [
                snapshot(id: "plain", isFavorite: false, area: 4_000, createdAt: Date(timeIntervalSince1970: 10)),
                snapshot(id: "favorite", isFavorite: true, area: 1_000, createdAt: Date(timeIntervalSince1970: 20)),
            ],
            completionDelay: {}
        )

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }

        viewModel.setBestShot("plain")
        await waitForRecordedManualPicks(1, on: metrics)
        await analyzer.finish(with: [])
        await loading.value

        let stored = await metrics.metrics
        #expect(stored.recommendationCount == 1)
        #expect(stored.manualOverrideCount == 1)
        #expect(abs(stored.overrideRate - 1) <= 0.000_1)
    }

    private func waitForRecordedManualPicks(
        _ expected: Int,
        on metrics: MockBestShotOverrideMetricsRepository,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<1_000 {
            let picks = await metrics.recordedManualPicks
            if picks.count >= expected { return }
            await Task.yield()
        }
        let picks = await metrics.recordedManualPicks
        #expect(picks.count == expected, sourceLocation: sourceLocation)
    }
}
