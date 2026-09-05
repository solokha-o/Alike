import Foundation

/// The seam callers depend on instead of the concrete
/// `BestShotPersonalizedScoringConfigProvider`, so a test can substitute a
/// double whose `config()` suspends on demand. The concrete actor caches for
/// good after its first successful load (see its `cache` documentation), so
/// it cannot itself be held open more than once — a protocol double is the
/// only way to pin a caller inside a second, later `config()` await.
public protocol BestShotConfigProviding: Sendable {
    /// The global config with the device's personalized weights applied on
    /// top, when there are any. Mirrors
    /// `BestShotPersonalizedScoringConfigProvider.config()`.
    func config() async -> PhotoQualityScoringConfig

    /// Records one manual-override example for on-device fitting. Mirrors
    /// `BestShotPersonalizedScoringConfigProvider.recordOverride(_:)`.
    func recordOverride(_ example: BestShotOverrideExample) async
}

/// Mediates between the global Best Shot scoring config and the device's
/// personalized weights, so every ranking call site sees the same
/// personalisation without duplicating the load/fit/cache logic.
///
/// An `actor`, not `@MainActor`: nothing here touches UI state, it only
/// mediates repository reads/writes and an in-memory cache. Ranking happens
/// from more than one call site, not all of them guaranteed to already be on
/// the main actor, and pinning this to `@MainActor` would force every one of
/// them to hop there just to read a config. An actor protects the cache at
/// the same cost without that constraint.
public actor BestShotPersonalizedScoringConfigProvider {
    /// Distinguishes "never loaded" from "loaded, and there is no
    /// personalisation yet" — both look like `nil` otherwise, and the
    /// difference is exactly what decides whether `config()` needs to hit the
    /// repository.
    private enum CacheState: Equatable {
        case notLoaded
        case loaded(BestShotPersonalWeights?)
    }

    private let repository: any BestShotPersonalizationRepository
    private let global: PhotoQualityScoringConfig
    private var cache: CacheState = .notLoaded

    /// Bumped by `reset()`, and only by `reset()`. `recordOverride` and
    /// `resolvedWeights` each capture this before their first suspension
    /// point and compare again after every subsequent `await`; a mismatch
    /// means a `reset()` ran while they were suspended, so whatever they
    /// were about to persist or publish is stale and gets dropped instead.
    /// `recordOverride`'s own recheck happens inside `commitLock` (see
    /// below), immediately before its write, so there is no window left
    /// between that check and the write for a `reset()` to land in — the
    /// old failure mode, where the check passed but a concurrent `reset()`'s
    /// write still ended up sandwiched underneath this one's, can no longer
    /// happen. This is what lets `recordOverride` run from an untracked
    /// `Task` (as Details does) without a slow, in-flight fit resurrecting
    /// weights or cache the user just asked to delete — and without a stale
    /// fit's eventual write being able to clobber a newer one either.
    private var generation = 0

    /// Guards the *commit* half of `recordOverride` — its generation
    /// recheck, `saveWeights`, and publishing `cache` — and all of
    /// `reset()`, so at most one of them is ever writing to the repository
    /// or `cache` at a time. `record`, `loadExamples`, and the synchronous
    /// fit in `recordOverride` all happen before this is acquired: only the
    /// part that could otherwise interleave with a concurrent `reset()` or
    /// `recordOverride` needs the lock. Whichever caller is already inside
    /// the section when a second one asks for it makes the second one wait,
    /// so a commit's own generation recheck is never stale by the time its
    /// write actually happens — see `acquireCommitLock()`.
    private var commitLocked = false
    private var commitWaiters: [CheckedContinuation<Void, Never>] = []

    /// Waits until no other `recordOverride`/`reset()` commit is in
    /// progress, then takes the lock. Pair with `releaseCommitLock()`
    /// (typically via `defer`) once inside.
    private func acquireCommitLock() async {
        guard commitLocked else {
            commitLocked = true
            return
        }
        await withCheckedContinuation { commitWaiters.append($0) }
    }

    /// Hands the lock to the next waiter, if any, or marks it free.
    private func releaseCommitLock() {
        guard commitWaiters.isEmpty else {
            commitWaiters.removeFirst().resume()
            return
        }
        commitLocked = false
    }

    public init(
        repository: any BestShotPersonalizationRepository,
        global: PhotoQualityScoringConfig = .current
    ) {
        self.repository = repository
        self.global = global
    }

    /// The global config with `weightsWithFaces` / `weightsWithoutFaces`
    /// replaced by the stored personal vectors. No stored weights (never
    /// personalised, or `reset()` since) returns `global` unchanged.
    public func config() async -> PhotoQualityScoringConfig {
        let weights = await resolvedWeights()
        guard let weights else { return global }
        var personalized = global
        personalized.weightsWithFaces = weights.withFaces
        personalized.weightsWithoutFaces = weights.withoutFaces
        return personalized
    }

    /// Records one override, refits over every stored example, and persists
    /// the result. Runs entirely on this actor: the caller is expected to
    /// fire this from a detached `Task` (the same convention the rest of this
    /// screen uses for `BestShotOverrideMetricsRepository`), so a slow refit
    /// never blocks the pick the user just made.
    ///
    /// `record`, `loadExamples`, and the fit all happen outside
    /// `commitLock`, so they can run concurrently with another commit; nothing
    /// here yet needs to be persisted or published. Only the recheck of
    /// `generation`, `saveWeights`, and updating `cache` run inside the lock,
    /// as one unit, so a `reset()` (or a newer `recordOverride`) that lands
    /// in between is impossible — whichever of them gets the lock first runs
    /// its check-then-write without any other commit able to interleave.
    /// `generation` is what tells a stale commit apart from a current one:
    /// if it moved since this call started, `reset()` already ran, so the
    /// fit above is discarded instead of persisted or cached.
    public func recordOverride(_ example: BestShotOverrideExample) async {
        let generationAtStart = generation
        await repository.record(example)
        let examples = await repository.loadExamples()
        guard generation == generationAtStart else { return }
        let fitted = PersonalWeightModel.personalWeights(from: examples, global: global)
        let withFacesCount = examples.filter { $0.clusterHasFaces }.count
        let weights = BestShotPersonalWeights(
            withFaces: fitted.withFaces,
            withoutFaces: fitted.withoutFaces,
            scoringModelVersion: global.scoringModelVersion,
            withFacesExampleCount: withFacesCount,
            withoutFacesExampleCount: examples.count - withFacesCount
        )
        await acquireCommitLock()
        defer { releaseCommitLock() }
        guard generation == generationAtStart else { return }
        await repository.saveWeights(weights)
        cache = .loaded(weights)
    }

    /// Clears both the stored and the in-memory personalisation, so the very
    /// next `config()` is the global config again without an app relaunch.
    ///
    /// Runs inside `commitLock`, the same section `recordOverride` commits
    /// through: if a `recordOverride` is already mid-commit, `reset()` waits
    /// for it to finish rather than racing it, so `generation` and `cache`
    /// only ever change between one commit finishing and the next one
    /// starting — never in the middle of one.
    public func reset() async {
        await acquireCommitLock()
        defer { releaseCommitLock() }
        generation += 1
        cache = .loaded(nil)
        await repository.reset()
    }

    private func resolvedWeights() async -> BestShotPersonalWeights? {
        switch cache {
        case .loaded(let weights):
            return weights
        case .notLoaded:
            let generationAtStart = generation
            let weights = await repository.loadWeights()
            guard generation == generationAtStart else {
                // A reset() landed while this load was in flight; trust its
                // result (already committed to `cache`) instead of the
                // pre-reset value this load just fetched.
                if case .loaded(let current) = cache { return current }
                return nil
            }
            cache = .loaded(weights)
            return weights
        }
    }
}

extension BestShotPersonalizedScoringConfigProvider: BestShotConfigProviding {}
