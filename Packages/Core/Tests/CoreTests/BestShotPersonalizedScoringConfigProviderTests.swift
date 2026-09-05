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

    // MARK: - Concurrency: reset and overlapping overrides
    //
    // `recordOverride` runs its whole transaction — record, snapshot, fit,
    // write, cache publication — inside `commitLock`, and `reset()` bumps
    // `generation` synchronously on entry and then clears inside the same
    // lock. `GatedBestShotPersonalizationRepository` lets a test park one of
    // those calls at a chosen repository await and release it on demand, so
    // the schedules below are driven rather than raced.
    //
    // Where a test needs to know that a second caller has entered the actor
    // and queued behind an open transaction, it waits on
    // `provider.commitWaiterCount` rather than yielding a fixed number of
    // times: a caller becomes a waiter only after everything synchronous
    // ahead of the wait has run, which for `reset()` includes the
    // `generation` bump.

    /// The reviewer's PR #58 P2: two overlapping overrides in the *same*
    /// generation. `generation` cannot tell them apart — only `reset()`
    /// moves it — so before the snapshot was pulled inside `commitLock`, an
    /// older `loadExamples` result could be fitted and written after a newer
    /// one had already committed, throwing away the newer example's
    /// learning until some later refit happened to pick it up (and reading
    /// back the stale weights across a relaunch in the meantime).
    ///
    /// Reproduces the reviewer's schedule: A takes its snapshot and parks,
    /// B tries to run to completion in the meantime, then A resumes. Against
    /// the previous code this fails with `withoutFacesExampleCount` 10 while
    /// 11 examples are stored; under serialisation B cannot even record its
    /// example until A is done, which is what the mid-test count assertion
    /// pins.
    func testAnOlderExampleSnapshotCannotOverwriteANewerFit() async {
        let repository = GatedBestShotPersonalizationRepository()
        await repository.setExamples((0..<9).map(staleExample(index:)))
        await repository.recordGate.open() // Not the resumption point under test.
        await repository.saveWeightsGate.open() // Writes themselves are not gated here.
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let exampleB = staleExample(index: 10)

        // A appends the tenth example and parks with that snapshot in hand.
        let exampleA = staleExample(index: 9)
        let taskA = Task { await provider.recordOverride(exampleA) }
        await repository.loadExamplesGate.waitUntilArrived()

        // B is the newer override. It must not be able to get in front of A.
        let taskB = Task { await provider.recordOverride(exampleB) }
        _ = await provider.waitForCommitWaiters(1)

        let examplesWhileAIsOpen = await repository.storedExampleCount
        XCTAssertEqual(
            examplesWhileAIsOpen,
            10,
            "a newer override must not take its own snapshot while an older transaction is still open"
        )

        await repository.loadExamplesGate.open()
        await taskA.value
        await taskB.value

        let storedExamples = await repository.storedExampleCount
        XCTAssertEqual(storedExamples, 11)
        let storedWeights = await repository.weights
        XCTAssertEqual(
            storedWeights?.withoutFacesExampleCount,
            11,
            "the persisted fit must be the newer one, over all 11 examples"
        )
        let config = await provider.config()
        XCTAssertEqual(
            config.weightsWithoutFaces,
            storedWeights?.withoutFaces,
            "the published cache and the repository must agree on the newer fit"
        )
    }

    /// An override that is still queued for `commitLock` when the user
    /// resets must be abandoned outright — it must not even record its
    /// example, let alone fit or persist one. This is what the `generation`
    /// bump on `reset()`'s entry buys: the reset invalidates the queued call
    /// immediately, rather than only once the reset's own turn on the lock
    /// comes round (by which point the queued call would already have
    /// committed).
    func testAnOverrideQueuedBehindAnOpenTransactionIsDroppedWhenAResetArrives() async {
        let repository = GatedBestShotPersonalizationRepository()
        await repository.loadExamplesGate.open() // Only `record()` is gated here.
        await repository.saveWeightsGate.open()
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let holdingExample = staleExample(index: 0)
        let invalidatedExample = staleExample(index: 1)

        // An unrelated override holds the lock open, parked inside `record()`.
        let holdingTask = Task { await provider.recordOverride(holdingExample) }
        await repository.recordGate.waitUntilArrived()

        // The stale override enters, captures the current generation, and
        // queues behind the open transaction.
        let staleTask = Task { await provider.recordOverride(invalidatedExample) }
        _ = await provider.waitForCommitWaiters(1)

        // The user resets. `generation` moves now, before the reset gets its
        // own turn on the lock.
        let resetTask = Task { await provider.reset() }
        _ = await provider.waitForCommitWaiters(2)

        await repository.recordGate.open()
        await holdingTask.value
        await staleTask.value
        await resetTask.value

        let recordedExamples = await repository.recordCallCount
        XCTAssertEqual(
            recordedExamples,
            1,
            "the queued override must be abandoned at the lock, without even recording its example"
        )
        let writes = await repository.saveWeightsCallCount
        XCTAssertEqual(writes, 0, "the reset invalidates both in-flight overrides, so neither may persist a fit")
        let didReset = await repository.didReset
        XCTAssertTrue(didReset)
        let configAfterRace = await provider.config()
        XCTAssertEqual(configAfterRace, global, "the reset must win: nothing personalised survives it")
    }

    /// The same guard one step later: here the override already holds the
    /// lock and has taken its snapshot when the reset arrives, so it is the
    /// recheck *after* the snapshot that has to catch it. It must perform no
    /// repository write at all — not write and then have something undo the
    /// write, which is indistinguishable from the outside if you only look
    /// at the stored weights.
    func testAnOpenTransactionThatSeesAResetArriveCommitsNothing() async {
        let repository = GatedBestShotPersonalizationRepository()
        await repository.setExamples([staleExample(index: 0)])
        await repository.recordGate.open()
        await repository.saveWeightsGate.open()
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let invalidatedExample = staleExample(index: 1)

        let recordTask = Task { await provider.recordOverride(invalidatedExample) }
        await repository.loadExamplesGate.waitUntilArrived()

        // `reset()` bumps `generation` on entry, then queues behind the open
        // transaction. Waiting for it to become a waiter is what makes the
        // bump ordered before the resumption below.
        let resetTask = Task { await provider.reset() }
        _ = await provider.waitForCommitWaiters(1)

        await repository.loadExamplesGate.open()
        await recordTask.value
        await resetTask.value

        let writes = await repository.saveWeightsCallCount
        XCTAssertEqual(writes, 0, "the transaction must bail out at its recheck, before writing anything")
        let storedWeights = await repository.weights
        XCTAssertNil(storedWeights, "a fit invalidated by a reset must not repopulate persisted weights")
        let survivingExamples = await repository.storedExampleCount
        XCTAssertEqual(survivingExamples, 0, "the reset clears the example the stale call did manage to record")
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
        // It never takes `commitLock`, so `reset()` below can be awaited
        // directly: ranking is deliberately not serialised against commits.
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

    /// `reset()` waits for an in-flight transaction instead of interleaving
    /// with it — the cost the serialisation deliberately accepts, and the
    /// reason `cache` and the repository can never disagree.
    func testAResetRequestedDuringAnOpenTransactionWaitsForItInsteadOfInterleaving() async {
        let repository = GatedBestShotPersonalizationRepository()
        await repository.recordGate.open()
        await repository.loadExamplesGate.open() // Only `saveWeights` is gated in this test.
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let example = staleExample(index: 0)

        let recordTask = Task { await provider.recordOverride(example) }
        await repository.saveWeightsGate.waitUntilArrived()

        let resetTask = Task { await provider.reset() }
        // Deterministic, unlike a bare `Task.yield()`: the reset is a waiter
        // only once it has entered the actor and reached the lock, so this
        // proves it is blocked rather than merely not scheduled yet.
        _ = await provider.waitForCommitWaiters(1)
        let resetLandedWhileCommitWasStillInFlight = await repository.didReset
        XCTAssertFalse(
            resetLandedWhileCommitWasStillInFlight,
            "reset() must wait for the open transaction's lock, not interleave with it"
        )

        await repository.saveWeightsGate.open()
        await recordTask.value
        await resetTask.value

        let storedWeights = await repository.weights
        XCTAssertNil(storedWeights, "reset() must win once it finally runs, even though it started mid-commit")
        let config = await provider.config()
        XCTAssertEqual(config, global, "the cache and the repository must agree: both reflect the reset")
    }

    /// A legitimate post-reset override still lands, and nothing the stale
    /// call did can take it away again. Covers the example half of the
    /// reviewer's earlier finding: at one point a stale call's recovery path
    /// could delete an example recorded after the user's reset.
    func testAPostResetOverrideSurvivesAStaleOverrideThatWasStillInFlight() async {
        let repository = GatedBestShotPersonalizationRepository()
        await repository.setExamples([staleExample(index: 0)])
        await repository.recordGate.open()
        await repository.saveWeightsGate.open()
        let provider = BestShotPersonalizedScoringConfigProvider(repository: repository, global: global)
        let exampleB = staleExample(index: 2)
        let invalidatedExample = staleExample(index: 1)

        let staleTask = Task { await provider.recordOverride(invalidatedExample) }
        await repository.loadExamplesGate.waitUntilArrived()

        let resetTask = Task { await provider.reset() }
        _ = await provider.waitForCommitWaiters(1)

        await repository.loadExamplesGate.open()
        await staleTask.value
        await resetTask.value

        // B is a legitimate post-reset override, run to completion.
        await provider.recordOverride(exampleB)

        let survivingExamples = await repository.loadExamples()
        XCTAssertEqual(survivingExamples.count, 1, "only B's post-reset example may remain")
        XCTAssertEqual(survivingExamples.first?.recordedAt, exampleB.recordedAt)
        let storedWeights = await repository.weights
        XCTAssertNotNil(storedWeights, "B's post-reset weights must be the ones left in the repository")
        XCTAssertEqual(storedWeights?.withoutFacesExampleCount, 1)
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

private extension BestShotPersonalizedScoringConfigProvider {
    /// Yields until at least `count` callers are parked waiting for
    /// `commitLock`, giving up after a bounded number of turns so a test
    /// that no longer produces the expected contention fails on its own
    /// assertions instead of hanging. Returns whether the count was reached.
    func waitForCommitWaiters(_ count: Int, maximumYields: Int = 10_000) async -> Bool {
        for _ in 0..<maximumYields {
            if commitWaiterCount >= count { return true }
            await Task.yield()
        }
        return commitWaiterCount >= count
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

/// A `BestShotPersonalizationRepository` test double whose `record()`,
/// `loadExamples()`, `loadWeights()` and `saveWeights()` can each be
/// suspended and resumed on demand via `SuspensionGate`, so a test can park
/// a `recordOverride`/`config()` at a chosen point and drive a second caller
/// against it deterministically.
private actor GatedBestShotPersonalizationRepository: BestShotPersonalizationRepository {
    let loadExamplesGate = SuspensionGate()
    let loadWeightsGate = SuspensionGate()
    let saveWeightsGate = SuspensionGate()
    let recordGate = SuspensionGate()

    private var examples: [BestShotOverrideExample] = []
    private(set) var weights: BestShotPersonalWeights?
    private(set) var didReset = false
    private(set) var saveWeightsCallCount = 0
    private(set) var recordCallCount = 0
    private var loadExamplesCallCount = 0

    /// Read directly rather than through `loadExamples()`, so a test can
    /// sample the stored state without tripping the gate on that method.
    var storedExampleCount: Int { examples.count }

    func setExamples(_ examples: [BestShotOverrideExample]) {
        self.examples = examples
    }

    func setWeights(_ weights: BestShotPersonalWeights?) {
        self.weights = weights
    }

    /// Only the *first* call is held, and the snapshot is taken before the
    /// gate rather than after it: that is what models a caller whose
    /// examples are already in hand while its continuation has not resumed
    /// yet — the shape of the older-snapshot race. Later calls (a second
    /// override, or a test's own assertion) run straight through.
    func loadExamples() async -> [BestShotOverrideExample] {
        let snapshot = examples
        loadExamplesCallCount += 1
        if loadExamplesCallCount == 1 {
            await loadExamplesGate.wait()
        }
        return snapshot
    }

    /// Only the first call is held, so a test can park one override inside
    /// its append while another runs.
    func record(_ example: BestShotOverrideExample) async {
        examples.append(example)
        recordCallCount += 1
        if recordCallCount == 1 {
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
