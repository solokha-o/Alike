import Foundation

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
    private enum CacheState {
        case notLoaded
        case loaded(BestShotPersonalWeights?)
    }

    private let repository: any BestShotPersonalizationRepository
    private let global: PhotoQualityScoringConfig
    private var cache: CacheState = .notLoaded

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
    public func recordOverride(_ example: BestShotOverrideExample) async {
        await repository.record(example)
        let examples = await repository.loadExamples()
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
    public func reset() async {
        await repository.reset()
        cache = .loaded(nil)
    }

    private func resolvedWeights() async -> BestShotPersonalWeights? {
        switch cache {
        case .loaded(let weights):
            return weights
        case .notLoaded:
            let weights = await repository.loadWeights()
            cache = .loaded(weights)
            return weights
        }
    }
}
