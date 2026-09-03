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
        public var topOneAgreement: Double
        public var blurryWinnerRate: Double
    }

    public static let defaultBlurPenalty = 5.0

    /// `objective = topOneAgreement - blurPenalty * blurryWinnerRate`, over the
    /// whole corpus. A cluster contributing `nil` to either metric (no resolved
    /// clusters, or no cluster produced a winner) counts as 0 for that metric
    /// rather than excluding the corpus from scoring entirely.
    public static func score(
        config: PhotoQualityScoringConfig,
        corpus: BestShotCalibrationCorpus,
        blurPenalty: Double = defaultBlurPenalty
    ) -> Score {
        let overall = MetricsReport.compute(corpus: corpus, config: config).overall
        let topOne = overall.topOneAgreement ?? 0
        let blurry = overall.blurryWinnerRate ?? 0
        return Score(
            objective: topOne - blurPenalty * blurry,
            topOneAgreement: topOne,
            blurryWinnerRate: blurry
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
