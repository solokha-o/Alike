import Core
import XCTest
@testable import Storage

final class UserDefaultsBestShotOverrideMetricsRepositoryTests: XCTestCase {
    /// Each test gets its own key in the standard suite, matching how the other
    /// `UserDefaults` repositories are tested here.
    private var key: String!

    override func setUp() {
        key = "bestShot.overrideMetrics.test.\(UUID().uuidString)"
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        key = nil
    }

    private var repository: UserDefaultsBestShotOverrideMetricsRepository {
        UserDefaultsBestShotOverrideMetricsRepository(key: key)
    }

    func testStartsEmpty() async {
        let metrics = await repository.loadMetrics()

        XCTAssertEqual(metrics, .empty)
        XCTAssertEqual(metrics.overrideRate, 0)
    }

    func testCountsRecommendationsAndOverrides() async {
        await repository.recordRecommendation(confidence: .automatic)
        await repository.recordRecommendation(confidence: .automatic)
        await repository.recordRecommendation(confidence: .lowConfidence)
        await repository.recordManualPick(replacing: .automatic)

        let metrics = await repository.loadMetrics()

        XCTAssertEqual(metrics.recommendationCount, 3)
        XCTAssertEqual(metrics.manualOverrideCount, 1)
        XCTAssertEqual(metrics.overrideRate, 1.0 / 3.0, accuracy: 0.000_1)
    }

    /// An unresolved cluster never recommended anything, so it cannot be a
    /// recommendation — nor an override when the user finally picks.
    func testUnresolvedClustersAreCountedSeparately() async {
        await repository.recordRecommendation(confidence: .unresolved)
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
        await repository.recordRecommendation(confidence: .automatic)

        let reopened = UserDefaultsBestShotOverrideMetricsRepository(key: key)
        let metrics = await reopened.loadMetrics()

        XCTAssertEqual(metrics.recommendationCount, 1)
    }

    func testResetClearsEverything() async {
        await repository.recordRecommendation(confidence: .automatic)
        await repository.recordManualPick(replacing: .automatic)

        await repository.resetMetrics()

        let metrics = await repository.loadMetrics()
        XCTAssertEqual(metrics, .empty)
    }

    /// Deleting local app data must take the counters with it.
    func testTheStorageKeyIsResettable() {
        XCTAssertTrue(AppPreferenceKey.resettable.contains(AppPreferenceKey.BestShot.overrideMetrics))
    }
}
