import Core
import Foundation

/// Deterministic, offline search for `PhotoQualityScoringConfig` weights and
/// thresholds that score better against a labelled corpus than the shipped
/// defaults.
///
/// Nothing here is random and nothing here writes back into `Core` — the
/// search only ever produces a candidate `PhotoQualityScoringConfig` value for
/// a human to review and, later, hand-apply.
public enum WeightSweep {
    // MARK: - Scoring

    public struct Score: Equatable {
        public var objective: Double
        /// The all-clusters figure the objective is actually built from. An
        /// unresolved cluster counts as a miss here, so refusing to answer can
        /// never raise this number the way it can raise `topOneAgreement`.
        public var topOneAgreementOverAllClusters: Double
        /// Reported for visibility only — coverage-dependent, see the doc
        /// comment on `MetricsReport.Bucket.topOneAgreement`. Never part of
        /// `objective`.
        public var topOneAgreement: Double
        public var coverageRate: Double
        public var blurryWinnerRate: Double
        /// The rate actually charged into `objective`:
        /// `(blurryWinnerCount + unresolvedCount) / clusterCount`. Unlike
        /// `blurryWinnerRate` (blurry winners over winners only), this treats
        /// an unresolved cluster as if it were a blurry winner, so it is
        /// always >= `blurryWinnerRate`. Reported separately so a report can
        /// show both the plain blurry-winner figure and the penalized one the
        /// objective is built from.
        public var penalizedBlurryRate: Double
    }

    public static let defaultBlurPenalty = 5.0

    /// `objective = topOneAgreementOverAllClusters - blurPenalty *
    /// penalizedBlurryRate`, over the whole corpus, where
    /// `penalizedBlurryRate = (blurryWinnerCount + unresolvedCount) /
    /// clusterCount`.
    ///
    /// The objective is built on `topOneAgreementOverAllClusters`, NOT the
    /// coverage-dependent `topOneAgreement` (over resolved clusters only).
    /// `topOneAgreement` can be raised simply by making the ranker refuse to
    /// answer more often — pushing clusters into `.unresolved` removes them
    /// from its denominator without the ranker having gotten anything more
    /// right. Measured on a real 75-cluster corpus, raising
    /// `absoluteSharpnessFloor` from 10 to 14 pushed `topOneAgreement` from
    /// 60.7% to 64.2% while the ranker got the exact same 34 of 75 clusters
    /// right the whole time — the search would have "improved" on pure
    /// avoidance. Scoring on `topOneAgreementOverAllClusters` counts an
    /// unresolved cluster as a miss in the agreement term.
    ///
    /// That alone is not enough: with `topOneAgreementOverAllClusters` as the
    /// only term, a config that resolves nothing scores exactly 0, and any
    /// config with a negative objective (from a costly blurry-winner penalty)
    /// would lose to it. So an unresolved cluster is ALSO charged into the
    /// penalty term, at the same per-cluster rate as a blurry winner
    /// (`penalizedBlurryRate` above). That is what makes refusing to answer
    /// strictly unprofitable: it can only ever cost objective, never gain it,
    /// relative to answering correctly and unblurred.
    ///
    /// A cluster contributing `nil` to either metric (no clusters at all, or
    /// no cluster produced a winner) counts as 0 for that metric rather than
    /// excluding the corpus from scoring entirely. An empty corpus
    /// (`clusterCount == 0`) scores an objective of 0.
    ///
    /// - Precondition: `blurPenalty` is finite and `>= 0`. A negative penalty
    ///   would turn the unresolved/blurry charge into a reward and hand the
    ///   search back exactly the all-unresolved winner this objective is built
    ///   to rule out; a NaN penalty makes every `>` comparison in the search
    ///   false, so it would silently keep whichever candidate it saw first.
    ///   Both are programmer error, not input to be tolerated — the CLI
    ///   rejects them at the argument boundary with a readable message.
    public static func score(
        config: PhotoQualityScoringConfig,
        corpus: BestShotCalibrationCorpus,
        blurPenalty: Double = defaultBlurPenalty
    ) -> Score {
        precondition(
            blurPenalty.isFinite && blurPenalty >= 0,
            "blurPenalty must be finite and >= 0, got \(blurPenalty)"
        )
        let overall = MetricsReport.compute(corpus: corpus, config: config).overall
        let topOneAllClusters = overall.topOneAgreementOverAllClusters ?? 0
        let topOne = overall.topOneAgreement ?? 0
        let blurry = overall.blurryWinnerRate ?? 0
        let penalizedBlurryRate = overall.clusterCount > 0
            ? Double(overall.blurryWinnerCount + overall.unresolvedCount) / Double(overall.clusterCount)
            : 0
        return Score(
            objective: topOneAllClusters - blurPenalty * penalizedBlurryRate,
            topOneAgreementOverAllClusters: topOneAllClusters,
            topOneAgreement: topOne,
            coverageRate: overall.coverageRate,
            blurryWinnerRate: blurry,
            penalizedBlurryRate: penalizedBlurryRate
        )
    }

    // MARK: - Result

    public struct Sample: Equatable {
        public var value: Double
        public var score: Score
    }

    public struct ParameterSensitivity: Equatable {
        public var parameterName: String
        public var samples: [Sample]
    }

    public struct Result: Equatable {
        public var baselineConfig: PhotoQualityScoringConfig
        public var baselineScore: Score
        public var candidateConfig: PhotoQualityScoringConfig
        public var candidateScore: Score
        /// Per-parameter grid, all other parameters held at `candidateConfig`.
        public var sensitivity: [ParameterSensitivity]
        public var blurPenalty: Double
    }

    // MARK: - Search

    private static let weightStep = 0.05
    private static let maxPasses = 5

    public static func run(
        corpus: BestShotCalibrationCorpus,
        baseline: PhotoQualityScoringConfig = .current,
        blurPenalty: Double = defaultBlurPenalty
    ) -> Result {
        let baselineScore = score(config: baseline, corpus: corpus, blurPenalty: blurPenalty)

        var current = baseline
        var currentScore = baselineScore

        for _ in 0..<maxPasses {
            var improvedThisPass = false

            let weightsStep = optimizeWeights(
                config: current,
                currentScore: currentScore,
                corpus: corpus,
                blurPenalty: blurPenalty
            )
            current = weightsStep.config
            currentScore = weightsStep.score
            improvedThisPass = improvedThisPass || weightsStep.improved

            let scalarsStep = optimizeScalars(
                config: current,
                currentScore: currentScore,
                corpus: corpus,
                blurPenalty: blurPenalty,
                gridBaseline: baseline
            )
            current = scalarsStep.config
            currentScore = scalarsStep.score
            improvedThisPass = improvedThisPass || scalarsStep.improved

            if !improvedThisPass { break }
        }

        let sensitivity = scalarParameters.map { parameter -> ParameterSensitivity in
            let grid = parameter.gridValues(parameter.get(baseline))
            let samples = grid.map { value -> Sample in
                var candidateConfig = current
                parameter.set(&candidateConfig, value)
                return Sample(
                    value: value,
                    score: score(config: candidateConfig, corpus: corpus, blurPenalty: blurPenalty)
                )
            }
            return ParameterSensitivity(parameterName: parameter.name, samples: samples)
        }

        return Result(
            baselineConfig: baseline,
            baselineScore: baselineScore,
            candidateConfig: current,
            candidateScore: currentScore,
            sensitivity: sensitivity,
            blurPenalty: blurPenalty
        )
    }

    // MARK: - Weight coordinate descent

    private enum WeightComponent: CaseIterable {
        case sharpness, faceQuality, exposure, noiseArtifacts, resolution

        var name: String {
            switch self {
            case .sharpness: return "sharpness"
            case .faceQuality: return "faceQuality"
            case .exposure: return "exposure"
            case .noiseArtifacts: return "noiseArtifacts"
            case .resolution: return "resolution"
            }
        }

        func value(in weights: PhotoQualityScoringConfig.Weights) -> Double {
            switch self {
            case .sharpness: return weights.sharpness
            case .faceQuality: return weights.faceQuality
            case .exposure: return weights.exposure
            case .noiseArtifacts: return weights.noiseArtifacts
            case .resolution: return weights.resolution
            }
        }
    }

    private enum WeightGroup: CaseIterable {
        case withFaces, withoutFaces

        var name: String {
            switch self {
            case .withFaces: return "weightsWithFaces"
            case .withoutFaces: return "weightsWithoutFaces"
            }
        }

        func weights(in config: PhotoQualityScoringConfig) -> PhotoQualityScoringConfig.Weights {
            switch self {
            case .withFaces: return config.weightsWithFaces
            case .withoutFaces: return config.weightsWithoutFaces
            }
        }

        func apply(_ weights: PhotoQualityScoringConfig.Weights, to config: PhotoQualityScoringConfig) -> PhotoQualityScoringConfig {
            var config = config
            switch self {
            case .withFaces: config.weightsWithFaces = weights
            case .withoutFaces: config.weightsWithoutFaces = weights
            }
            return config
        }
    }

    /// Sets `component` to `newValue` and rescales the other four components
    /// proportionally so `Weights.total` stays exactly 1. When the other four
    /// are all zero (degenerate — nothing to scale proportionally), the
    /// remainder is split evenly across them instead.
    private static func withComponent(
        _ weights: PhotoQualityScoringConfig.Weights,
        _ component: WeightComponent,
        setTo newValue: Double
    ) -> PhotoQualityScoringConfig.Weights {
        let clamped = min(max(newValue, 0), 1)
        let others = WeightComponent.allCases.filter { $0 != component }
        let othersOldSum = others.reduce(0) { $0 + $1.value(in: weights) }
        let remainder = 1 - clamped

        var values: [WeightComponent: Double] = [component: clamped]
        if othersOldSum > 1e-9 {
            let scale = remainder / othersOldSum
            for other in others {
                values[other] = other.value(in: weights) * scale
            }
        } else {
            let share = remainder / Double(others.count)
            for other in others {
                values[other] = share
            }
        }

        return PhotoQualityScoringConfig.Weights(
            sharpness: values[.sharpness] ?? 0,
            faceQuality: values[.faceQuality] ?? 0,
            exposure: values[.exposure] ?? 0,
            noiseArtifacts: values[.noiseArtifacts] ?? 0,
            resolution: values[.resolution] ?? 0
        )
    }

    private struct StepResult {
        var config: PhotoQualityScoringConfig
        var score: Score
        var improved: Bool
    }

    private static func optimizeWeights(
        config: PhotoQualityScoringConfig,
        currentScore: Score,
        corpus: BestShotCalibrationCorpus,
        blurPenalty: Double
    ) -> StepResult {
        var config = config
        var best = currentScore
        var improved = false

        for group in WeightGroup.allCases {
            for component in WeightComponent.allCases {
                let weights = group.weights(in: config)
                let baseValue = component.value(in: weights)

                var candidates: [(value: Double, config: PhotoQualityScoringConfig, score: Score)] = []
                for delta in [-weightStep, weightStep] {
                    let newValue = baseValue + delta
                    guard newValue >= 0, newValue <= 1 else { continue }
                    let newWeights = withComponent(weights, component, setTo: newValue)
                    let candidateConfig = group.apply(newWeights, to: config)
                    let candidateScore = score(config: candidateConfig, corpus: corpus, blurPenalty: blurPenalty)
                    candidates.append((newValue, candidateConfig, candidateScore))
                }

                guard let chosen = bestImproving(candidates, over: best) else { continue }
                config = chosen.config
                best = chosen.score
                improved = true
            }
        }

        return StepResult(config: config, score: best, improved: improved)
    }

    // MARK: - Scalar grid search

    private struct ScalarParameter: @unchecked Sendable {
        let name: String
        let get: @Sendable (PhotoQualityScoringConfig) -> Double
        let set: @Sendable (inout PhotoQualityScoringConfig, Double) -> Void
        let gridValues: @Sendable (Double) -> [Double]
    }

    /// A fixed, symmetric grid of `count` points spaced `step` apart around
    /// `center` — the shipped default for that parameter, never the value the
    /// descent may have already moved it to.
    /// `halfWidth` points on each side of `center`, so `halfWidth: 2` yields 5
    /// grid points in total: `center - 2*step ... center + 2*step`.
    private static func symmetricGrid(around center: Double, step: Double, halfWidth: Int) -> [Double] {
        (-halfWidth...halfWidth).map { max(0, center + Double($0) * step) }
    }

    private static let scalarParameters: [ScalarParameter] = [
        ScalarParameter(
            name: "criticalSharpnessRatio",
            get: { $0.criticalSharpnessRatio },
            set: { $0.criticalSharpnessRatio = $1 },
            gridValues: { symmetricGrid(around: $0, step: 0.05, halfWidth: 2) }
        ),
        ScalarParameter(
            name: "strongPenaltySharpnessRatio",
            get: { $0.strongPenaltySharpnessRatio },
            set: { $0.strongPenaltySharpnessRatio = $1 },
            gridValues: { symmetricGrid(around: $0, step: 0.05, halfWidth: 2) }
        ),
        ScalarParameter(
            name: "weakPenaltySharpnessRatio",
            get: { $0.weakPenaltySharpnessRatio },
            set: { $0.weakPenaltySharpnessRatio = $1 },
            gridValues: { symmetricGrid(around: $0, step: 0.05, halfWidth: 2) }
        ),
        ScalarParameter(
            name: "absoluteSharpnessFloor",
            get: { $0.absoluteSharpnessFloor },
            set: { $0.absoluteSharpnessFloor = $1 },
            gridValues: { symmetricGrid(around: $0, step: 2, halfWidth: 2) }
        ),
        ScalarParameter(
            name: "automaticSelectionMinimumScore",
            get: { $0.automaticSelectionMinimumScore },
            set: { $0.automaticSelectionMinimumScore = $1 },
            gridValues: { symmetricGrid(around: $0, step: 0.05, halfWidth: 2) }
        ),
        ScalarParameter(
            name: "automaticSelectionMinimumMargin",
            get: { $0.automaticSelectionMinimumMargin },
            set: { $0.automaticSelectionMinimumMargin = $1 },
            gridValues: { symmetricGrid(around: $0, step: 0.02, halfWidth: 2) }
        ),
    ]

    private static func optimizeScalars(
        config: PhotoQualityScoringConfig,
        currentScore: Score,
        corpus: BestShotCalibrationCorpus,
        blurPenalty: Double,
        gridBaseline: PhotoQualityScoringConfig
    ) -> StepResult {
        var config = config
        var best = currentScore
        var improved = false

        for parameter in scalarParameters {
            let grid = parameter.gridValues(parameter.get(gridBaseline))
            var candidates: [(value: Double, config: PhotoQualityScoringConfig, score: Score)] = []
            for value in grid {
                var candidateConfig = config
                parameter.set(&candidateConfig, value)
                let candidateScore = score(config: candidateConfig, corpus: corpus, blurPenalty: blurPenalty)
                candidates.append((value, candidateConfig, candidateScore))
            }

            guard let chosen = bestImproving(candidates, over: best) else { continue }
            config = chosen.config
            best = chosen.score
            improved = true
        }

        return StepResult(config: config, score: best, improved: improved)
    }

    // MARK: - Tie-break

    /// Fixed, deterministic tie-break: higher objective wins; ties go to the
    /// lower `blurryWinnerRate`; remaining ties go to the candidate whose new
    /// parameter value is numerically smaller, so the same corpus always
    /// produces the same winner regardless of evaluation order.
    private static func bestImproving(
        _ candidates: [(value: Double, config: PhotoQualityScoringConfig, score: Score)],
        over current: Score
    ) -> (value: Double, config: PhotoQualityScoringConfig, score: Score)? {
        let improving = candidates.filter { isBetter($0.score, than: current) }
        guard !improving.isEmpty else { return nil }
        return improving.min { lhs, rhs in
            if lhs.score.objective != rhs.score.objective {
                return lhs.score.objective > rhs.score.objective
            }
            if lhs.score.blurryWinnerRate != rhs.score.blurryWinnerRate {
                return lhs.score.blurryWinnerRate < rhs.score.blurryWinnerRate
            }
            return lhs.value < rhs.value
        }
    }

    private static func isBetter(_ candidate: Score, than current: Score) -> Bool {
        if candidate.objective != current.objective {
            return candidate.objective > current.objective
        }
        return candidate.blurryWinnerRate < current.blurryWinnerRate
    }
}
