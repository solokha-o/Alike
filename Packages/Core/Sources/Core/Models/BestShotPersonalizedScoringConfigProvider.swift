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
    /// were about to persist or publish is stale. Before the write to the
    /// repository, that is a plain drop. After it — `recordOverride`'s
    /// `saveWeights` call itself already completed by the time the mismatch
    /// is observed — the write already landed, possibly on top of a
    /// legitimately newer `reset()` or `recordOverride`, so it is repaired
    /// from `cache` (see `repairRepositoryFromCache()`) instead of dropped.
    /// This is what lets `recordOverride` run from an untracked `Task` (as
    /// Details does) without a slow, in-flight fit resurrecting weights or
    /// cache the user just asked to delete — and without a stale fit's
    /// eventual write being able to clobber a newer one either.
    private var generation = 0

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
    /// That also makes this reentrant at every `await` below: `reset()` can
    /// run to completion while this call is suspended. `generation` is the
    /// guard against the fit finishing after such a reset and repopulating
    /// what the user just cleared — the fit and the write below still
    /// happen, but the result is discarded instead of persisted or cached if
    /// a `reset()` was observed in between.
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
        await repository.saveWeights(weights)
        guard generation == generationAtStart else {
            // A reset() — or another recordOverride that started after this
            // one and already ran to completion — landed while `saveWeights`
            // above was in flight, so that write just persisted stale
            // weights on top of whatever is now current. `repository.reset()`
            // (the old fix) was just as wrong as leaving the stale write in
            // place: `reset()` also deletes examples, and by the time this
            // runs a newer `recordOverride` may already have recorded one
            // that has every right to still be there. `cache` only ever
            // tracks weights, so it is repaired with the weights-only
            // `clearWeights()` / `saveWeights()` instead — never with
            // `reset()`, which would risk the examples it doesn't track.
            await repairRepositoryFromCache()
            return
        }
        cache = .loaded(weights)
    }

    /// Restores the repository's weights to whatever `cache` currently says
    /// is true. Only reached from `recordOverride`, after its own
    /// `saveWeights` write already landed but turned out to be stale
    /// (`reset()`, or a newer `recordOverride`, committed while it was in
    /// flight) — the write itself can't be taken back, so this puts the
    /// weights back in sync with the more recent state `cache` is already
    /// holding. Deliberately never touches examples: `cache` isn't an
    /// authoritative snapshot of them, so `saveWeights`/`clearWeights` are
    /// used here instead of `reset()`.
    ///
    /// `cache` is also the last thing any non-stale caller touches, and
    /// always synchronously, right before its own repository call — so if it
    /// moved again while the write below was in flight, a still-newer
    /// `reset()` or `recordOverride` already landed and this write is now
    /// itself the stale one. The loop repeats against that fresher snapshot
    /// instead of leaving a superseded write in place, which is what keeps a
    /// repair from clobbering a generation newer than the one it read.
    private func repairRepositoryFromCache() async {
        while true {
            guard case .loaded(let authoritative) = cache else { return }
            let cacheBeforeRepair = cache
            if let authoritative {
                await repository.saveWeights(authoritative)
            } else {
                await repository.clearWeights()
            }
            if cache == cacheBeforeRepair { return }
        }
    }

    /// Clears both the stored and the in-memory personalisation, so the very
    /// next `config()` is the global config again without an app relaunch.
    ///
    /// Bumps `generation` and updates `cache` before the repository round
    /// trip — both synchronously, with no `await` between them — so any
    /// `recordOverride`/`resolvedWeights` call already in flight sees the
    /// mismatch once it resumes and either drops its stale result or, in
    /// `recordOverride`'s post-save case, repairs from `cache`. Setting
    /// `cache` here rather than after the repository call closes the window
    /// where a repair would otherwise read a not-yet-updated `cache`.
    public func reset() async {
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
