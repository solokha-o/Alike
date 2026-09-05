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

    /// Bumped by `reset()`, and only by `reset()` — synchronously at its
    /// entry, *before* it waits for `commitLock`, so an override that is
    /// already queued behind an in-flight commit is invalidated the moment
    /// the user asks for a reset rather than only once the reset's own turn
    /// comes round. `recordOverride` captures this before its first
    /// suspension point and rechecks it inside the lock; `resolvedWeights`
    /// does the same across its load. A mismatch means a `reset()` has
    /// happened or is guaranteed to happen next, so whatever the caller was
    /// about to persist or publish is stale and gets dropped instead. This
    /// is what lets `recordOverride` run from an untracked `Task` (as
    /// Details does) without a slow, in-flight fit resurrecting weights the
    /// user just asked to delete.
    private var generation = 0

    /// Serialises the whole of `recordOverride` — `record`, `loadExamples`,
    /// the fit, `saveWeights`, and publishing `cache` — against every other
    /// `recordOverride` and against `reset()`'s own clearing, so at most one
    /// of them is ever reading or writing the personalisation at a time.
    ///
    /// The snapshot has to be inside the section, not just the write: two
    /// overrides in the same generation both pass the generation guard, so
    /// if only the write were serialised, an older `loadExamples` snapshot
    /// could still be fitted and committed after a newer one had already
    /// landed, silently discarding the newer example's learning until the
    /// next refit. Nothing outside this actor can order two snapshots
    /// after the fact — the repository hands back an array with no
    /// revision, and the example count is not a version because the store
    /// is a ring buffer — so the only sound fix is to stop the second
    /// snapshot from being taken while the first transaction is open.
    ///
    /// The cost, deliberately accepted: `reset()` waits for an in-flight
    /// override transaction (one `UserDefaults` append, one read, a bounded
    /// fit over at most the ring buffer's worth of examples, one write)
    /// rather than racing it. `config()`/`resolvedWeights` never take this
    /// lock, so ranking is never blocked by a fit.
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

    /// Test seam: how many callers are currently parked waiting for
    /// `commitLock`. A caller only becomes a waiter after it has entered the
    /// actor and run everything synchronous ahead of the wait — for
    /// `reset()` that includes bumping `generation` — so a concurrency test
    /// can observe "the reset has landed and is now queued behind the open
    /// transaction" deterministically instead of guessing with
    /// `Task.yield()`. Internal, so it adds no shipped surface.
    var commitWaiterCount: Int { commitWaiters.count }

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
    /// The entire transaction runs inside `commitLock`, so a second override
    /// cannot take its snapshot until this one has committed and can never
    /// fit an example set older than what is already persisted. `generation`
    /// is checked twice: once on acquiring the lock, so an override the user
    /// has already invalidated by resetting never even records its example,
    /// and once after the snapshot, to catch a `reset()` that arrived while
    /// this transaction was open. Either way the fit is discarded rather
    /// than persisted or cached, and `reset()` — which is waiting on the
    /// same lock — clears whatever this call did record.
    public func recordOverride(_ example: BestShotOverrideExample) async {
        let generationAtStart = generation
        await acquireCommitLock()
        defer { releaseCommitLock() }
        guard generation == generationAtStart else { return }
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
        await repository.saveWeights(weights)
        cache = .loaded(weights)
    }

    /// Clears both the stored and the in-memory personalisation, so the very
    /// next `config()` is the global config again without an app relaunch.
    ///
    /// `generation` moves first, synchronously and outside `commitLock`, so
    /// an override already queued behind an in-flight transaction is
    /// invalidated immediately instead of getting its turn and committing a
    /// fit the user has just discarded. The clearing itself runs inside the
    /// lock, so it lands after any transaction already in progress rather
    /// than in the middle of one — `cache` and the repository always end up
    /// agreeing.
    public func reset() async {
        generation += 1
        await acquireCommitLock()
        defer { releaseCommitLock() }
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
