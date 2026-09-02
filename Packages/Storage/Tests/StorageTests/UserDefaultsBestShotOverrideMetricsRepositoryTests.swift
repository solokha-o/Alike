import Core
import XCTest
@testable import Storage

final class UserDefaultsBestShotOverrideMetricsRepositoryTests: XCTestCase {
    /// Each test gets its own key in the standard suite, matching how the other
    /// `UserDefaults` repositories are tested here.
    private var key: String!
    private var countedClustersKey: String!

    override func setUp() {
        key = "bestShot.overrideMetrics.test.\(UUID().uuidString)"
        countedClustersKey = "bestShot.countedClusters.test.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: countedClustersKey)
        key = nil
        countedClustersKey = nil
    }

    private var repository: UserDefaultsBestShotOverrideMetricsRepository {
        UserDefaultsBestShotOverrideMetricsRepository(
            key: key,
            countedClustersKey: countedClustersKey
        )
    }

    func testStartsEmpty() async {
        let metrics = await repository.loadMetrics()

        XCTAssertEqual(metrics, .empty)
        XCTAssertEqual(metrics.overrideRate, 0)
    }

    func testCountsRecommendationsAndOverrides() async {
        await repository.recordRecommendation(confidence: .automatic, clusterID: UUID())
        await repository.recordRecommendation(confidence: .automatic, clusterID: UUID())
        await repository.recordRecommendation(confidence: .lowConfidence, clusterID: UUID())
        await repository.recordManualPick(replacing: .automatic)

        let metrics = await repository.loadMetrics()

        XCTAssertEqual(metrics.recommendationCount, 3)
        XCTAssertEqual(metrics.manualOverrideCount, 1)
        XCTAssertEqual(metrics.overrideRate, 1.0 / 3.0, accuracy: 0.000_1)
    }

    /// An unresolved cluster never recommended anything, so it cannot be a
    /// recommendation — nor an override when the user finally picks.
    func testUnresolvedClustersAreCountedSeparately() async {
        await repository.recordRecommendation(confidence: .unresolved, clusterID: UUID())
        await repository.recordManualPick(replacing: .unresolved)

        let metrics = await repository.loadMetrics()

        XCTAssertEqual(metrics.recommendationCount, 0)
        XCTAssertEqual(metrics.manualOverrideCount, 0)
        XCTAssertEqual(metrics.unresolvedManualPickCount, 1)
    }

    func testLowConfidenceOverridesAreTrackedApart() async {
        await repository.recordManualPick(replacing: .lowConfidence)

        let metrics = await repository.loadMetrics()

        XCTAssertEqual(metrics.manualOverrideCount, 1)
        XCTAssertEqual(metrics.lowConfidenceOverrideCount, 1)
    }

    func testCountersSurviveANewRepositoryInstance() async {
        await repository.recordRecommendation(confidence: .automatic, clusterID: UUID())

        let reopened = UserDefaultsBestShotOverrideMetricsRepository(
            key: key,
            countedClustersKey: countedClustersKey
        )
        let metrics = await reopened.loadMetrics()

        XCTAssertEqual(metrics.recommendationCount, 1)
    }

    /// The denominator counts clusters, the numerator counts replacements; a
    /// revisit must not dilute the rate the calibration target is read from.
    func testReopeningTheSameClusterIsCountedOnce() async {
        let clusterID = UUID()

        await repository.recordRecommendation(confidence: .automatic, clusterID: clusterID)
        await repository.recordRecommendation(confidence: .automatic, clusterID: clusterID)
        await repository.recordRecommendation(confidence: .lowConfidence, clusterID: clusterID)
        await repository.recordManualPick(replacing: .automatic)

        let metrics = await repository.loadMetrics()
        XCTAssertEqual(metrics.recommendationCount, 1)
        XCTAssertEqual(metrics.overrideRate, 1, accuracy: 0.000_1)
    }

    func testResetClearsEverything() async {
        await repository.recordRecommendation(confidence: .automatic, clusterID: UUID())
        await repository.recordManualPick(replacing: .automatic)

        await repository.resetMetrics()

        let metrics = await repository.loadMetrics()
        XCTAssertEqual(metrics, .empty)

        // The dedupe list goes too, or the counters could never grow again.
        await repository.recordRecommendation(confidence: .automatic, clusterID: UUID())
        let afterReset = await repository.loadMetrics()
        XCTAssertEqual(afterReset.recommendationCount, 1)
    }

    /// Deleting local app data must take the counters with it.
    func testTheStorageKeyIsResettable() {
        XCTAssertTrue(AppPreferenceKey.resettable.contains(AppPreferenceKey.BestShot.overrideMetrics))
        XCTAssertTrue(
            AppPreferenceKey.resettable.contains(AppPreferenceKey.BestShot.countedRecommendationClusters)
        )
    }
}
