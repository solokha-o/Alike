import XCTest
@testable import Core

final class BestShotPersonalizedScoringConfigProviderTests: XCTestCase {
    private let global = PhotoQualityScoringConfig.current

    func testNoStoredWeightsReturnsGlobalConfigUnchanged() async {
        let repository = MockBestShotPersonalizationRepository()
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)

        let config = await provider.config()

        XCTAssertEqual(config, global)
    }

    func testStoredWeightsAreCarriedIntoTheConfig() async {
        let repository = MockBestShotPersonalizationRepository()
        let personal = BestShotPersonalWeights(
            withFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.30,
                faceQuality: 0.35,
                exposure: 0.20,
                noiseArtifacts: 0.10,
                resolution: 0.05
            ),
            withoutFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.65,
                faceQuality: 0,
                exposure: 0.20,
                noiseArtifacts: 0.10,
                resolution: 0.05
            ),
            scoringModelVersion: global.scoringModelVersion,
            withFacesExampleCount: 25,
            withoutFacesExampleCount: 15
        )
        await repository.setWeights(personal)
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)

        let config = await provider.config()

        XCTAssertEqual(config.weightsWithFaces, personal.withFaces)
        XCTAssertEqual(config.weightsWithoutFaces, personal.withoutFaces)
        // Everything else about the config is untouched.
        XCTAssertEqual(config.scoringModelVersion, global.scoringModelVersion)
        XCTAssertEqual(config.favoriteBonus, global.favoriteBonus)
    }

    func testResetMakesTheNextConfigCallGlobalAgain() async {
        let repository = MockBestShotPersonalizationRepository()
        let personal = BestShotPersonalWeights(
            withFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.30,
                faceQuality: 0.35,
                exposure: 0.20,
                noiseArtifacts: 0.10,
                resolution: 0.05
            ),
            withoutFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.65,
                faceQuality: 0,
                exposure: 0.20,
                noiseArtifacts: 0.10,
                resolution: 0.05
            ),
            scoringModelVersion: global.scoringModelVersion,
            withFacesExampleCount: 25,
            withoutFacesExampleCount: 15
        )
        await repository.setWeights(personal)
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let personalizedConfig = await provider.config()
        XCTAssertNotEqual(personalizedConfig, global)

        await provider.reset()
        let configAfterReset = await provider.config()

        XCTAssertEqual(configAfterReset, global)
        let didReset = await repository.didReset
        XCTAssertTrue(didReset)
    }

    func testRecordOverrideRefitsAndCachesTheResult() async {
        let repository = MockBestShotPersonalizationRepository()
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)

        for index in 0..<20 {
            let example = BestShotOverrideExample(
                recordedAt: Date(timeIntervalSince1970: Double(index)),
                clusterHasFaces: false,
                componentDelta: PhotoQualityScoringConfig.Weights(
                    sharpness: -0.3,
                    faceQuality: 0,
                    exposure: 0.3,
                    noiseArtifacts: 0,
                    resolution: 0
                ),
                offsetDelta: 0,
                scoringModelVersion: global.scoringModelVersion
            )
            await provider.recordOverride(example)
        }

        let storedWeights = await repository.weights
        XCTAssertNotNil(storedWeights)
        XCTAssertEqual(storedWeights?.withoutFacesExampleCount, 20)

        // The cache reflects the fit without another repository round trip.
        let config = await provider.config()
        XCTAssertEqual(config.weightsWithoutFaces, storedWeights?.withoutFaces)
        XCTAssertNotEqual(config.weightsWithoutFaces, global.weightsWithoutFaces)
    }

    // MARK: - Reset vs. a stale in-flight recordOverride/config (generation guard)
    //
    // `recordOverride` and `resolvedWeights` are reentrant at every `await`:
    // `reset()` can run to completion while either is suspended inside the
    // repository. `GatedBestShotPersonalizationRepository` lets a test
    // suspend one of those awaits on demand and resume it only after
    // `reset()` has already committed, proving the stale invocation cannot
    // repopulate persisted weights or the published cache/`resolvedWeights`.

    func testResetStaysEffectiveAgainstARecordOverrideThatResumesAfterIt() async {
        let repository = GatedBestShotPersonalizationRepository()
        await repository.setExamples([staleExample(index: 0)])
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let newExample = staleExample(index: 1)

        let recordTask = Task {
            await provider.recordOverride(newExample)
        }

        // Let recordOverride get past `record()` and suspend inside the
        // `loadExamples()` await — the exact resumption point the reviewer
        // describes.
        await repository.loadExamplesGate.waitUntilArrived()

        await provider.reset()

        // Only now does the stale invocation get to resume and try to fit
        // and persist from the pre-reset examples.
        await repository.loadExamplesGate.open()
        await recordTask.value

        let storedWeights = await repository.weights
        XCTAssertNil(storedWeights, "a record that resumes after reset must not repopulate persisted weights")

        let configAfterRace = await provider.config()
        XCTAssertEqual(configAfterRace, global, "the published config must also stay un-personalised")
    }

    func testResetStaysEffectiveAgainstAConfigLoadThatResumesAfterIt() async {
        let repository = GatedBestShotPersonalizationRepository()
        let stalePersonal = BestShotPersonalWeights(
            withFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.30, faceQuality: 0.35, exposure: 0.20, noiseArtifacts: 0.10, resolution: 0.05
            ),
            withoutFaces: PhotoQualityScoringConfig.Weights(
                sharpness: 0.65, faceQuality: 0, exposure: 0.20, noiseArtifacts: 0.10, resolution: 0.05
            ),
            scoringModelVersion: global.scoringModelVersion,
            withFacesExampleCount: 25,
            withoutFacesExampleCount: 15
        )
        await repository.setWeights(stalePersonal)
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)

        let configTask = Task {
            await provider.config()
        }

        // Let `config()` get as far as suspending inside `loadWeights()`.
        await repository.loadWeightsGate.waitUntilArrived()

        await provider.reset()

        // Only now does the in-flight `config()` get to resume with the
        // pre-reset weights it already fetched.
        await repository.loadWeightsGate.open()
        let raceResult = await configTask.value

        XCTAssertEqual(raceResult, global, "a config() started before reset must not surface stale weights once it resumes")

        let configAfterRace = await provider.config()
        XCTAssertEqual(configAfterRace, global, "the cache must reflect the reset, not the stale load")
    }

    func testResetUndoesAStaleWriteThatLandsInSaveWeightsAfterIt() async {
        let repository = GatedBestShotPersonalizationRepository()
        await repository.loadExamplesGate.open() // Only `saveWeights` is gated in this test.
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let newExample = staleExample(index: 0)

        let recordTask = Task {
            await provider.recordOverride(newExample)
        }

        // Let recordOverride get all the way through the fit and suspend
        // inside `saveWeights()` — the exact resumption point the reviewer's
        // "stale invocation repopulates persisted weights" complaint
        // targets, since that write happens before the post-save guard.
        await repository.saveWeightsGate.waitUntilArrived()

        await provider.reset()

        // Only now does the stale invocation get to land its write.
        await repository.saveWeightsGate.open()
        await recordTask.value

        let storedWeights = await repository.weights
        XCTAssertNil(storedWeights, "a save that lands after reset must not repopulate persisted weights")

        let configAfterRace = await provider.config()
        XCTAssertEqual(configAfterRace, global, "the published config must also stay un-personalised")
    }

    func testANewOverrideThatCompletesWhileAStaleSaveIsStillInFlightSurvivesTheStaleSaveLandingLast() async {
        // The reviewer's stacked race: a stale `recordOverride` (gen N) is
        // parked inside `saveWeights`; a real `reset()` (gen N+1) runs to
        // completion; a brand-new `recordOverride` (also gen N+1) runs
        // start to finish and persists; only then does the stale call's
        // `saveWeights` land. A corrective `repository.reset()` at that
        // point would wipe the new override along with the stale one —
        // this asserts the new override survives instead.
        let repository = GatedBestShotPersonalizationRepository()
        await repository.loadExamplesGate.open() // Only `saveWeights` is gated.
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let staleExampleValue = staleExample(index: 0)

        let staleTask = Task {
            await provider.recordOverride(staleExampleValue)
        }

        // Let the stale call get all the way through the fit and suspend
        // inside `saveWeights()`.
        await repository.saveWeightsGate.waitUntilArrived()

        await provider.reset()

        // A brand-new override arrives and completes in full while the
        // stale call is still parked.
        let newExamples = (1...20).map { staleExample(index: $0) }
        for newExample in newExamples {
            await provider.recordOverride(newExample)
        }
        let weightsAfterNewOverride = await repository.weights
        XCTAssertNotNil(weightsAfterNewOverride, "the new override must have persisted before the stale call resumes")

        // Only now does the stale call's write land.
        await repository.saveWeightsGate.open()
        await staleTask.value

        let storedWeights = await repository.weights
        XCTAssertEqual(
            storedWeights, weightsAfterNewOverride,
            "a stale save landing after a newer override must not clobber it"
        )

        let configAfterRace = await provider.config()
        var expectedConfig = global
        expectedConfig.weightsWithFaces = weightsAfterNewOverride!.withFaces
        expectedConfig.weightsWithoutFaces = weightsAfterNewOverride!.withoutFaces
        XCTAssertEqual(
            configAfterRace, expectedConfig,
            "config()/resolvedWeights() must also keep reflecting the newer override"
        )
    }

    private func staleExample(index: Int) -> BestShotOverrideExample {
        BestShotOverrideExample(
            recordedAt: Date(timeIntervalSince1970: Double(index)),
            clusterHasFaces: false,
            componentDelta: PhotoQualityScoringConfig.Weights(
                sharpness: -0.3, faceQuality: 0, exposure: 0.3, noiseArtifacts: 0, resolution: 0
            ),
            offsetDelta: 0,
            scoringModelVersion: global.scoringModelVersion
        )
    }
}

/// A one-shot gate whose `wait()` suspends until `open()` is called,
/// letting a test park an `await` mid-flight and release it on demand.
/// `waitUntilArrived()` lets the test block until some other task is
/// actually parked inside `wait()`, so the race being tested is
/// deterministic instead of depending on task-scheduling luck.
private actor SuspensionGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            arrivalContinuation?.resume()
            arrivalContinuation = nil
        }
    }

    func waitUntilArrived() async {
        if continuation != nil || isOpen { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

/// A `BestShotPersonalizationRepository` test double whose `loadExamples()`
/// and `loadWeights()` can each be suspended and resumed on demand via
/// `SuspensionGate`, to deterministically land a `reset()` in the middle of
/// an in-flight `recordOverride`/`config()` call.
private actor GatedBestShotPersonalizationRepository: BestShotPersonalizationRepository {
    let loadExamplesGate = SuspensionGate()
    let loadWeightsGate = SuspensionGate()
    let saveWeightsGate = SuspensionGate()

    private var examples: [BestShotOverrideExample] = []
    private(set) var weights: BestShotPersonalWeights?
    private(set) var didReset = false
    /// Only the first `saveWeights` call is held on `saveWeightsGate` — every
    /// later one goes straight through. That is what lets a test park one
    /// stale `recordOverride` mid-save while a second, later one completes
    /// and persists normally in the meantime.
    private var saveWeightsCallCount = 0

    func setExamples(_ examples: [BestShotOverrideExample]) {
        self.examples = examples
    }

    func setWeights(_ weights: BestShotPersonalWeights?) {
        self.weights = weights
    }

    func loadExamples() async -> [BestShotOverrideExample] {
        await loadExamplesGate.wait()
        return examples
    }

    func record(_ example: BestShotOverrideExample) async {
        examples.append(example)
    }

    func loadWeights() async -> BestShotPersonalWeights? {
        await loadWeightsGate.wait()
        return weights
    }

    func saveWeights(_ weights: BestShotPersonalWeights) async {
        saveWeightsCallCount += 1
        if saveWeightsCallCount == 1 {
            await saveWeightsGate.wait()
        }
        self.weights = weights
    }

    func reset() async {
        didReset = true
        examples = []
        weights = nil
    }
}
