import Core
import Foundation
import Testing
@testable import Storage

/// A `final class` suite: each test gets its own `UserDefaults` suite, and `deinit`
/// removes it. The repository is an actor and `UserDefaults` is not `Sendable`, so
/// each repository gets its own `UserDefaults` instance of that suite.
@Suite final class UserDefaultsBestShotOverrideMetricsRepositoryTests {
    private let suiteName = UUID().uuidString
    private let defaults: UserDefaults
    private let key = "bestShot.overrideMetrics.test.\(UUID().uuidString)"
    private let countedClustersKey = "bestShot.countedClusters.test.\(UUID().uuidString)"

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var repository: UserDefaultsBestShotOverrideMetricsRepository {
        UserDefaultsBestShotOverrideMetricsRepository(
            defaults: UserDefaults(suiteName: suiteName)!,
            key: key,
            countedClustersKey: countedClustersKey
        )
    }

    @Test func testStartsEmpty() async {
        let metrics = await repository.loadMetrics()

        #expect(metrics == .empty)
        #expect(metrics.overrideRate == 0)
    }

    @Test func testCountsRecommendationsAndOverrides() async {
        let overriddenCluster = UUID()
        await repository.recordRecommendation(confidence: .automatic, clusterID: overriddenCluster)
        await repository.recordRecommendation(confidence: .automatic, clusterID: UUID())
        await repository.recordRecommendation(confidence: .lowConfidence, clusterID: UUID())
        await repository.recordManualPick(replacing: .automatic, clusterID: overriddenCluster)

        let metrics = await repository.loadMetrics()

        #expect(metrics.recommendationCount == 3)
        #expect(metrics.manualOverrideCount == 1)
        let eps = 0.000_1
        #expect(abs(metrics.overrideRate - (1.0 / 3.0)) <= eps)
    }

    /// An unresolved cluster never recommended anything, so it cannot be a
    /// recommendation — nor an override when the user finally picks.
    @Test func testUnresolvedClustersAreCountedSeparately() async {
        await repository.recordRecommendation(confidence: .unresolved, clusterID: UUID())
        await repository.recordManualPick(replacing: .unresolved, clusterID: UUID())

        let metrics = await repository.loadMetrics()

        #expect(metrics.recommendationCount == 0)
        #expect(metrics.manualOverrideCount == 0)
        #expect(metrics.unresolvedManualPickCount == 1)
    }

    @Test func testLowConfidenceOverridesAreTrackedApart() async {
        let cluster = UUID()
        await repository.recordRecommendation(confidence: .lowConfidence, clusterID: cluster)
        await repository.recordManualPick(replacing: .lowConfidence, clusterID: cluster)

        let metrics = await repository.loadMetrics()

        #expect(metrics.manualOverrideCount == 1)
        #expect(metrics.lowConfidenceOverrideCount == 1)
    }

    /// The rate must describe the same clusters on both sides: an override for a
    /// cluster whose recommendation was never counted cannot push it past 1.
    @Test func testAnOverrideWithoutACountedRecommendationIsNotCounted() async {
        await repository.recordManualPick(replacing: .automatic, clusterID: UUID())

        let metrics = await repository.loadMetrics()

        #expect(metrics.recommendationCount == 0)
        #expect(metrics.manualOverrideCount == 0)
        #expect(metrics.overrideRate == 0)
    }

    @Test func testCountersSurviveANewRepositoryInstance() async {
        await repository.recordRecommendation(confidence: .automatic, clusterID: UUID())

        let reopened = UserDefaultsBestShotOverrideMetricsRepository(
            defaults: UserDefaults(suiteName: suiteName)!,
            key: key,
            countedClustersKey: countedClustersKey
        )
        let metrics = await reopened.loadMetrics()

        #expect(metrics.recommendationCount == 1)
    }

    /// The denominator counts clusters, the numerator counts replacements; a
    /// revisit must not dilute the rate the calibration target is read from.
    @Test func testReopeningTheSameClusterIsCountedOnce() async {
        let clusterID = UUID()

        await repository.recordRecommendation(confidence: .automatic, clusterID: clusterID)
        await repository.recordRecommendation(confidence: .automatic, clusterID: clusterID)
        await repository.recordRecommendation(confidence: .lowConfidence, clusterID: clusterID)
        await repository.recordManualPick(replacing: .automatic, clusterID: clusterID)

        let metrics = await repository.loadMetrics()
        #expect(metrics.recommendationCount == 1)
        let eps = 0.000_1
        #expect(abs(metrics.overrideRate - 1) <= eps)
    }

    @Test func testResetClearsEverything() async {
        let cluster = UUID()
        await repository.recordRecommendation(confidence: .automatic, clusterID: cluster)
        await repository.recordManualPick(replacing: .automatic, clusterID: cluster)

        await repository.resetMetrics()

        let metrics = await repository.loadMetrics()
        #expect(metrics == .empty)

        // The dedupe list goes too, or the counters could never grow again.
        await repository.recordRecommendation(confidence: .automatic, clusterID: UUID())
        let afterReset = await repository.loadMetrics()
        #expect(afterReset.recommendationCount == 1)
    }

    /// Deleting local app data must take the counters with it.
    @Test func testTheStorageKeyIsResettable() {
        #expect(AppPreferenceKey.resettable.contains(AppPreferenceKey.BestShot.overrideMetrics))
        #expect(
            AppPreferenceKey.resettable.contains(AppPreferenceKey.BestShot.countedRecommendationClusters)
        )
    }
}
