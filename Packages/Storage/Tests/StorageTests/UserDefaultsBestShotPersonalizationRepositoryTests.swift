import Core
import XCTest
@testable import Storage

final class UserDefaultsBestShotPersonalizationRepositoryTests: XCTestCase {
    private var suiteName: String!
    private var examplesKey: String!
    private var weightsKey: String!

    override func setUp() {
        suiteName = "UserDefaultsBestShotPersonalizationRepositoryTests.\(UUID().uuidString)"
        examplesKey = "bestShot.overrideExamples.test"
        weightsKey = "bestShot.personalWeights.test"
    }

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        suiteName = nil
        examplesKey = nil
        weightsKey = nil
    }

    private var repository: UserDefaultsBestShotPersonalizationRepository {
        UserDefaultsBestShotPersonalizationRepository(
            defaults: UserDefaults(suiteName: suiteName)!,
            examplesKey: examplesKey,
            weightsKey: weightsKey
        )
    }

    private func makeExample(
        recordedAt: Date = Date(),
        clusterHasFaces: Bool = true,
        scoringModelVersion: Int = PhotoQualityScoringConfig.current.scoringModelVersion
    ) -> BestShotOverrideExample {
        BestShotOverrideExample(
            recordedAt: recordedAt,
            clusterHasFaces: clusterHasFaces,
            componentDelta: PhotoQualityScoringConfig.Weights(
                sharpness: 0.1,
                faceQuality: 0.05,
                exposure: 0.02,
                noiseArtifacts: 0.01,
                resolution: 0.0
            ),
            offsetDelta: 0.03,
            scoringModelVersion: scoringModelVersion
        )
    }

    private func makeWeights(
        scoringModelVersion: Int = PhotoQualityScoringConfig.current.scoringModelVersion
    ) -> BestShotPersonalWeights {
        BestShotPersonalWeights(
            withFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.42,
                faceQuality: 0.23,
                exposure: 0.19,
                noiseArtifacts: 0.11,
                resolution: 0.05
            ),
            withoutFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.53,
                faceQuality: 0,
                exposure: 0.26,
                noiseArtifacts: 0.16,
                resolution: 0.05
            ),
            scoringModelVersion: scoringModelVersion,
            withFacesExampleCount: 12,
            withoutFacesExampleCount: 4
        )
    }

    func testStartsEmpty() async {
        let examples = await repository.loadExamples()
        let weights = await repository.loadWeights()

        XCTAssertTrue(examples.isEmpty)
        XCTAssertNil(weights)
    }

    func testRoundTripsExamples() async {
        let example = makeExample()
        await repository.record(example)

        let examples = await repository.loadExamples()

        XCTAssertEqual(examples, [example])
    }

    func testRoundTripsWeights() async {
        let weights = makeWeights()
        await repository.saveWeights(weights)

        let loaded = await repository.loadWeights()

        XCTAssertEqual(loaded, weights)
    }

    func testSavingWeightsReplacesThePreviousValue() async {
        await repository.saveWeights(makeWeights())
        let replacement = makeWeights()
        await repository.saveWeights(replacement)

        let loaded = await repository.loadWeights()

        XCTAssertEqual(loaded, replacement)
    }

    /// Past the cap, the oldest example is dropped first and insertion order
    /// is preserved among the survivors.
    func testCapsAtFiveHundredDroppingTheOldestFirst() async {
        let repository = repository
        for index in 0..<520 {
            await repository.record(makeExample(recordedAt: Date(timeIntervalSince1970: Double(index))))
        }

        let examples = await repository.loadExamples()

        XCTAssertEqual(examples.count, 500)
        XCTAssertEqual(examples.first?.recordedAt, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(examples.last?.recordedAt, Date(timeIntervalSince1970: 519))
    }

    /// Examples measured under a different scoring formula must never be
    /// reinterpreted against the current one.
    func testLoadExamplesFiltersOutAStaleScoringModelVersion() async {
        let current = makeExample(scoringModelVersion: PhotoQualityScoringConfig.current.scoringModelVersion)
        let stale = makeExample(scoringModelVersion: PhotoQualityScoringConfig.current.scoringModelVersion + 1)
        await repository.record(stale)
        await repository.record(current)

        let examples = await repository.loadExamples()

        XCTAssertEqual(examples, [current])
    }

    func testLoadWeightsReturnsNilForAStaleScoringModelVersion() async {
        let stale = makeWeights(scoringModelVersion: PhotoQualityScoringConfig.current.scoringModelVersion + 1)
        await repository.saveWeights(stale)

        let loaded = await repository.loadWeights()

        XCTAssertNil(loaded)
    }

    func testResetClearsBothExamplesAndWeights() async {
        await repository.record(makeExample())
        await repository.saveWeights(makeWeights())

        await repository.reset()

        let examples = await repository.loadExamples()
        let weights = await repository.loadWeights()
        XCTAssertTrue(examples.isEmpty)
        XCTAssertNil(weights)
    }

    func testCorruptExamplesDataYieldsEmptyRatherThanCrashing() async {
        UserDefaults(suiteName: suiteName)!.set(Data([0x00, 0x01, 0x02]), forKey: examplesKey)

        let examples = await repository.loadExamples()

        XCTAssertTrue(examples.isEmpty)
    }

    func testCorruptWeightsDataYieldsNilRatherThanCrashing() async {
        UserDefaults(suiteName: suiteName)!.set(Data([0x00, 0x01, 0x02]), forKey: weightsKey)

        let weights = await repository.loadWeights()

        XCTAssertNil(weights)
    }

    func testDataSurvivesANewRepositoryInstance() async {
        let example = makeExample()
        let weights = makeWeights()
        await repository.record(example)
        await repository.saveWeights(weights)

        let reopened = UserDefaultsBestShotPersonalizationRepository(
            defaults: UserDefaults(suiteName: suiteName)!,
            examplesKey: examplesKey,
            weightsKey: weightsKey
        )

        let examples = await reopened.loadExamples()
        let loadedWeights = await reopened.loadWeights()
        XCTAssertEqual(examples, [example])
        XCTAssertEqual(loadedWeights, weights)
    }

    /// Deleting local app data must take the personalization data with it.
    func testTheStorageKeysAreResettable() {
        XCTAssertTrue(AppPreferenceKey.resettable.contains(AppPreferenceKey.BestShot.overrideExamples))
        XCTAssertTrue(AppPreferenceKey.resettable.contains(AppPreferenceKey.BestShot.personalWeights))
    }
}
