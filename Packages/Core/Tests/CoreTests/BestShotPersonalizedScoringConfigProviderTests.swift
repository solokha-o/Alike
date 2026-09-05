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

    /// `testResetStaysEffectiveAgainstARecordOverrideThatResumesAfterIt`
    /// above already proves that a `recordOverride` parked at the
    /// `loadExamples()` await — the only suspension point before
    /// `commitLock` is taken — cannot repopulate weights once a `reset()`
    /// has run first. This test used to park *inside* `saveWeights()`
    /// instead, modelling a stale write "landing after" a reset that had
    /// already happened; that schedule no longer exists now that
    /// `saveWeights` runs under `commitLock` for the whole call, so parking
    /// there and then calling `reset()` deadlocked forever waiting on a lock
    /// the parked call already held — that hang is why this test needed
    /// rework. Parking before the lock, the way the test above does, is the
    /// only schedule the current code permits, so that is what this now
    /// does too.
    ///
    /// What this still adds on top of that existing test: proof that the
    /// stale commit bails out *before* ever calling `saveWeights`, not that
    /// it writes and then some repair step undoes the write. Both look
    /// identical from `repository.weights` alone (`nil` either way) — that
    /// was exactly the gap the old repair-based code exploited, since it
    /// wrote first and called `repository.reset()` to clean up afterwards.
    /// `saveWeightsCallCount == 0` is the one assertion that tells the two
    /// apart, and it is genuinely new coverage: nothing else in this file
    /// pins "no write happened" rather than "no write survived".
    ///
    /// Weaker than the original claim: the original name promised a write
    /// "landing after" reset; this proves there is no write at all. That is
    /// the correct, and only remaining, way to express the invariant the
    /// original test was reaching for.
    func testAStaleRecordOverrideThatResumesAfterResetPerformsNoRepositoryWrite() async {
        let repository = GatedBestShotPersonalizationRepository()
        await repository.setExamples([staleExample(index: 0)])
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let newExample = staleExample(index: 1)

        let recordTask = Task {
            await provider.recordOverride(newExample)
        }

        // Let recordOverride get past `record()` and suspend inside
        // `loadExamples()` — the only await before `commitLock` is taken, so
        // `reset()` below is free to run without waiting on anything.
        await repository.loadExamplesGate.waitUntilArrived()

        await provider.reset()

        // Only now does the stale invocation resume, fit from what is now a
        // stale example set, and try to commit.
        await repository.loadExamplesGate.open()
        await recordTask.value

        let storedWeights = await repository.weights
        XCTAssertNil(storedWeights, "a commit that finds `generation` moved must not repopulate persisted weights")
        let didReset = await repository.didReset
        XCTAssertTrue(didReset)
        let writes = await repository.saveWeightsCallCount
        XCTAssertEqual(writes, 0, "the stale commit must bail out at its generation recheck, not write and then repair")

        let configAfterRace = await provider.config()
        XCTAssertEqual(configAfterRace, global, "the published config must also stay un-personalised")
    }

    /// The reviewer's stacked race this test used to drive — a stale
    /// `recordOverride` parked inside `saveWeights`, a `reset()` running to
    /// completion in between, then a brand-new `recordOverride` completing
    /// before the stale save finally landed — can no longer happen: A now
    /// holds `commitLock` for the whole of its `saveWeights` call, so a
    /// concurrent `reset()` cannot get in front of it, and neither can a
    /// second `recordOverride`, which would itself block on the same lock.
    /// Driving the old schedule here deadlocks instead of racing, which is
    /// exactly why the old version of this test hung.
    ///
    /// What replaced it: the property the lock actually adds is that
    /// `reset()` *waits* for an in-flight commit instead of interleaving
    /// with it. This parks A inside `saveWeights` (so it holds the lock for
    /// the rest of the call), starts `reset()` concurrently, and checks —
    /// after giving the scheduler one turn — that the repository has not
    /// seen a reset yet.
    ///
    /// That intermediate check is best-effort and is the one place this
    /// test understates what it proves: it can only under-report (a
    /// `reset()` task the scheduler has not yet run also reads as "no reset
    /// happened"), so it cannot fail spuriously, but a run where the
    /// scheduler never gives `reset()` a turn before the sample would pass
    /// without having exercised the block at all. The two closing
    /// assertions do not share that weakness — they hold unconditionally,
    /// because the test explicitly awaits both tasks to completion, so
    /// whichever order they actually interleaved in, the repository and the
    /// published cache must agree by the time both are done.
    func testAResetRequestedDuringAnInFlightCommitWaitsForItInsteadOfInterleaving() async {
        let repository = GatedBestShotPersonalizationRepository()
        await repository.loadExamplesGate.open() // Only saveWeights is gated in this test.
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let example = staleExample(index: 0)

        let recordTask = Task {
            await provider.recordOverride(example)
        }

        // recordOverride takes commitLock before calling saveWeights, so by
        // the time this gate is reached the lock is held for the rest of
        // the call.
        await repository.saveWeightsGate.waitUntilArrived()

        let resetTask = Task {
            await provider.reset()
        }

        // Give reset() a chance to actually attempt the lock. See the type
        // doc comment above for what this can and cannot prove.
        await Task.yield()
        let resetLandedWhileCommitWasStillInFlight = await repository.didReset
        XCTAssertFalse(
            resetLandedWhileCommitWasStillInFlight,
            "reset() must wait for the in-flight commit's lock, not interleave with it"
        )

        await repository.saveWeightsGate.open()
        await recordTask.value
        await resetTask.value

        let storedWeights = await repository.weights
        XCTAssertNil(storedWeights, "reset() must win once it finally runs, even though it started mid-commit")
        let config = await provider.config()
        XCTAssertEqual(config, global, "the cache and the repository must agree: both reflect the reset")
    }

    /// The example half of the reviewer's PR #58 findings: a stale
    /// `recordOverride` must not be able to delete an example a newer one
    /// recorded after the user's reset.
    ///
    /// The reviewer's original schedule parked A inside `saveWeights` and
    /// then ran `reset()`; that cannot be driven any more, because A now
    /// holds `commitLock` for the whole of its write and `reset()` would
    /// wait rather than interleave — the test would hang, not fail. A is
    /// therefore parked at the last await *before* the lock is taken, which
    /// leaves `reset()` free to run and still has A resume into a world
    /// where its fit is stale.
    ///
    /// With the repair path deleted there is no longer any code that can
    /// remove an example except `reset()` itself, so this is now a guard
    /// against reintroducing one rather than a reproduction of a live bug.
    /// It overlaps `testAStaleCommitPerformsNoRepositoryWriteAfterAReset`,
    /// which drives the same schedule and asserts on the weights; kept
    /// separate because the examples are a different stored value and were
    /// the thing actually lost.
    func testAStaleCommitDoesNotDeleteAnExampleRecordedAfterTheReset() async {
        let repository = GatedBestShotPersonalizationRepository()
        await repository.recordGate.open() // Not the resumption point under test here.
        await repository.saveWeightsGate.open() // Writes themselves are not gated here.
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let exampleA = staleExample(index: 0)
        let exampleB = staleExample(index: 1)

        // 1. A records its example and parks on `loadExamples`, before it
        // has taken `commitLock`.
        let taskA = Task {
            await provider.recordOverride(exampleA)
        }
        await repository.loadExamplesGate.waitUntilArrived()

        // 2. `reset()` completes, clearing A's example along with everything
        // else — which is exactly what the user asked for.
        await provider.reset()

        // 3. A resumes into a stale world and must commit nothing.
        await repository.loadExamplesGate.open()
        await taskA.value

        // 4. B is a legitimate post-reset override, run to completion.
        await provider.recordOverride(exampleB)

        let survivingExamples = await repository.loadExamples()
        XCTAssertEqual(survivingExamples.count, 1, "only B's post-reset example may remain")
        XCTAssertEqual(survivingExamples.first?.recordedAt, exampleB.recordedAt)
    }

    /// The durability half of the reviewer's PR #58 finding: a stale
    /// `recordOverride` must not be able to destroy a newer override's
    /// persisted weights.
    ///
    /// The reviewer's own five-step schedule — A's write landed, then
    /// `reset()`, then B's write landed but unpublished, then A resumes and
    /// repairs from a `cache` that still reads nil — cannot be expressed
    /// against this code any more, and that is the point of the fix rather
    /// than a gap in the test: A now holds `commitLock` across its own
    /// check-and-write, so `reset()` cannot land in the middle of it and
    /// there is no post-write repair left to misfire. Driving that schedule
    /// here would simply deadlock on the lock.
    ///
    /// So this pins the invariant that makes the schedule impossible: a
    /// commit that finds `generation` moved performs **no repository write
    /// at all**, which is what `saveWeightsCallCount` asserts.
    ///
    /// Be honest about what that is worth: this test passes against the
    /// previous, repair-based code too, because parking on `loadExamples`
    /// resumes A into that version's *earlier* guard, which already returned
    /// before writing. It is a guard against regression, not a reproduction
    /// of the bug. The only schedule that told the two versions apart parked
    /// A inside `saveWeights` — and under `commitLock` that one cannot be
    /// driven at all, since `reset()` would then wait on the lock A holds
    /// rather than racing it. That is the fix working, but it does mean no
    /// test in this file fails against the pre-fix provider.
    func testAStaleCommitPerformsNoRepositoryWriteAfterAReset() async {
        let repository = GatedBestShotPersonalizationRepository()
        await repository.recordGate.open() // Not the resumption point under test.
        await repository.saveWeightsGate.open() // Writes themselves are not gated here.
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let exampleA = staleExample(index: 0)
        let exampleB = staleExample(index: 1)

        // A starts and parks before it can commit: it has recorded its
        // example and is waiting on `loadExamples`, so it has not taken
        // `commitLock` yet and `reset()` below is free to run.
        let taskA = Task { await provider.recordOverride(exampleA) }
        await repository.loadExamplesGate.waitUntilArrived()

        await provider.reset()

        // A resumes into a world where its fit is stale.
        await repository.loadExamplesGate.open()
        await taskA.value

        // B is a legitimate post-reset override, run to completion.
        await provider.recordOverride(exampleB)

        let storedWeights = await repository.weights
        XCTAssertNotNil(storedWeights, "B's post-reset weights must be the ones left in the repository")
        XCTAssertEqual(storedWeights?.withoutFacesExampleCount, 1)
        let writes = await repository.saveWeightsCallCount
        XCTAssertEqual(writes, 1, "the stale commit must not write to the repository at all — only B's write may land")
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
    /// Gates the *second* `record(_:)` call, so a test can park a second,
    /// later `recordOverride` right after it has appended its example — the
    /// exact resumption point the reviewer's five-step schedule needs — while
    /// a first `recordOverride` is free to run straight through this method.
    let recordGate = SuspensionGate()

    private var examples: [BestShotOverrideExample] = []
    private(set) var weights: BestShotPersonalWeights?
    private(set) var didReset = false
    /// Only the first `saveWeights` call is held on `saveWeightsGate` — every
    /// later one goes straight through. That is what lets a test park one
    /// stale `recordOverride` mid-save while a second, later one completes
    /// and persists normally in the meantime. The count is also read directly
    /// by tests asserting that a stale commit issued no write at all.
    private(set) var saveWeightsCallCount = 0
    private var recordCallCount = 0
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
        recordCallCount += 1
        if recordCallCount == 2 {
            await recordGate.wait()
        }
    }

    func loadWeights() async -> BestShotPersonalWeights? {
        await loadWeightsGate.wait()
        return weights
    }

    func saveWeights(_ weights: BestShotPersonalWeights) async {
        // The mutation lands immediately, before any gate — modelling a
        // repository write that has already completed even though the
        // caller's own continuation (the `await` below returning) hasn't
        // resumed yet.
        self.weights = weights
        saveWeightsCallCount += 1
        if saveWeightsCallCount == 1 {
            await saveWeightsGate.wait()
        }
    }

    func reset() async {
        didReset = true
        examples = []
        weights = nil
    }
}
