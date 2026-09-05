import Foundation

/// Turns a user's Best Shot override examples into personalised weight
/// vectors that *adjust* the global scoring rather than replace it.
///
/// Pure and deterministic: the same examples always produce the same
/// vectors, with no I/O, no randomness and no wall-clock dependency. The
/// output is weights only — nothing about the sharpness floor, the penalty
/// ratios, the confidence gate or any face-detection parameter is
/// expressible through this API, so a few stray taps can never turn a
/// blurred frame into a Best Shot; they can only retune how much sharpness
/// counts relative to exposure, noise, resolution and face quality.
public enum PersonalWeightModel {
    /// Below this many examples on a branch, the fit is not run at all and
    /// that branch's global vector is returned unchanged. A handful of taps
    /// must not move anything.
    static let minimumExamples = 10

    /// Fixed gradient-ascent step count and learning rate. These are pinned
    /// constants, not tuned per call: the fit must be reproducible from the
    /// input array alone, so nothing here may depend on convergence checks,
    /// wall-clock time, or per-example scale. 200 steps at 0.5 converges the
    /// log-likelihood gradient (whose components are bounded by the O(1)
    /// score deltas the ranker produces) comfortably within the ridge-created
    /// basin for realistic override volumes (tens to low hundreds of
    /// examples), with headroom for pathological but finite inputs.
    ///
    /// The likelihood gradient below is the *mean* over examples, not the
    /// sum: summing would scale that term by n while the ridge term stays
    /// O(1), so beyond a few dozen examples the likelihood would dominate
    /// the ridge outright, beta would slam into the box on every component,
    /// and n's influence on the outcome would collapse to "which box corner"
    /// instead of the intended "how far along `shrinkageFactor`". Averaging
    /// keeps the likelihood term on the same O(1) scale as the ridge
    /// regardless of n, so the two stay balanced and n enters the result
    /// only through shrinkage, as designed.
    private static let iterationCount = 200
    private static let learningRate = 0.5
    /// Load-bearing, not decoration: every override example is by
    /// construction a "chosen beat recommended" observation, so every label
    /// fed to the logistic fit is 1. With all labels 1 the unpenalised
    /// log-likelihood is maximised by sending beta to infinity along the
    /// mean-delta direction — there is no finite maximum without a penalty.
    /// The ridge term anchors the fit to the global vector and, now that the
    /// likelihood term is averaged rather than summed, is the only thing
    /// that keeps beta finite *and* the only term whose scale is fixed
    /// independent of n.
    private static let ridgeLambda = 1.0

    /// Half-width of the box a personalized component may move within,
    /// around the matching global component.
    private static let boxRadius = 0.15

    /// Fixed bisection step count for `project`. `components(shift:).total`
    /// is continuous and non-increasing in the shift (each clipped component
    /// is individually non-increasing), so bisection on a bracket where it
    /// changes sign converges monotonically toward the unique root; the
    /// bracket built from the box bounds is at most a few units wide (weights
    /// and the box radius are all O(1)), so 60 halvings already lands past
    /// `Double`'s ~52 bits of mantissa precision. Fixed like `iterationCount`
    /// above, for the same reason: reproducible from the input alone, no
    /// convergence check.
    private static let projectionBisectionSteps = 60

    /// Fits `withFaces` and `withoutFaces` independently from the matching
    /// branch of `examples`, then shrinks and projects each result back onto
    /// the allowed weight simplex around the global vector.
    ///
    /// Examples never cross branches: `faceQuality` is structurally 0 in a
    /// faceless cluster, so a faceless example carries no information about
    /// the face weight, and mixing the branches would let one branch's
    /// examples move the other branch's output.
    public static func personalWeights(
        from examples: [BestShotOverrideExample],
        global: PhotoQualityScoringConfig = .current
    ) -> (withFaces: PhotoQualityScoringConfig.Weights, withoutFaces: PhotoQualityScoringConfig.Weights) {
        let withFacesExamples = examples.filter { $0.clusterHasFaces }
        let withoutFacesExamples = examples.filter { !$0.clusterHasFaces }

        let withFaces = fitBranch(
            examples: withFacesExamples,
            global: global.weightsWithFaces,
            resolutionWeightCap: global.resolutionWeightCap,
            pinFaceQualityToZero: false
        )
        let withoutFaces = fitBranch(
            examples: withoutFacesExamples,
            global: global.weightsWithoutFaces,
            resolutionWeightCap: global.resolutionWeightCap,
            pinFaceQualityToZero: true
        )
        return (withFaces, withoutFaces)
    }

    // MARK: - Per-branch fit

    private static func fitBranch(
        examples: [BestShotOverrideExample],
        global: PhotoQualityScoringConfig.Weights,
        resolutionWeightCap: Double,
        pinFaceQualityToZero: Bool
    ) -> PhotoQualityScoringConfig.Weights {
        let n = examples.count
        guard n >= minimumExamples else { return global }

        // Guard against non-finite input up front: an example whose delta or
        // offset is not finite cannot contribute a meaningful gradient step.
        let usable = examples.filter { example in
            example.componentDelta.sharpness.isFinite
                && example.componentDelta.faceQuality.isFinite
                && example.componentDelta.exposure.isFinite
                && example.componentDelta.noiseArtifacts.isFinite
                && example.componentDelta.resolution.isFinite
                && example.offsetDelta.isFinite
        }
        guard usable.count >= minimumExamples else { return global }

        guard let fitted = gradientAscent(examples: usable, global: global) else { return global }

        let alpha = shrinkageFactor(n: usable.count)
        let shrunk = interpolate(global, fitted, alpha: alpha)

        guard let projected = project(
            shrunk,
            global: global,
            resolutionWeightCap: resolutionWeightCap,
            pinFaceQualityToZero: pinFaceQualityToZero
        ) else { return global }
        return projected
    }

    /// Plain gradient ascent on the ridge-penalised log-likelihood, starting
    /// from the global vector. Returns `nil` if beta ever becomes non-finite,
    /// which abandons the fit rather than propagate garbage.
    private static func gradientAscent(
        examples: [BestShotOverrideExample],
        global: PhotoQualityScoringConfig.Weights
    ) -> PhotoQualityScoringConfig.Weights? {
        let globalVector = Vector5(global)
        var beta = globalVector
        let deltas = examples.map { (delta: Vector5($0.componentDelta), offset: $0.offsetDelta) }

        for _ in 0..<iterationCount {
            var gradient = Vector5.zero
            for (delta, offset) in deltas {
                let z = beta.dot(delta) + offset
                let sigma = 1 / (1 + exp(-z))
                gradient = gradient + delta.scaled(by: 1 - sigma)
            }
            // Mean, not sum: dividing by n keeps the likelihood term on the
            // same O(1) scale as the ridge regardless of how much evidence
            // there is, so the ridge can actually balance it. See the
            // comment on `ridgeLambda` for what goes wrong without this.
            gradient = gradient.scaled(by: 1 / Double(deltas.count))
            let ridgeTerm = (beta - globalVector).scaled(by: ridgeLambda)
            gradient = gradient - ridgeTerm

            let updated = beta + gradient.scaled(by: learningRate)
            guard updated.isFinite else { return nil }
            beta = updated
        }
        return beta.asWeights
    }

    /// alpha(10) is approximately 0.06, alpha(30) is exactly 0.25, alpha(200)
    /// is approximately 0.72: a few overrides barely move the global vector,
    /// a couple of hundred move it substantially.
    private static func shrinkageFactor(n: Int) -> Double {
        max(0, Double(n - 5) / Double(n - 5 + 75))
    }

    private static func interpolate(
        _ global: PhotoQualityScoringConfig.Weights,
        _ fitted: PhotoQualityScoringConfig.Weights,
        alpha: Double
    ) -> PhotoQualityScoringConfig.Weights {
        PhotoQualityScoringConfig.Weights(
            sharpness: (1 - alpha) * global.sharpness + alpha * fitted.sharpness,
            faceQuality: (1 - alpha) * global.faceQuality + alpha * fitted.faceQuality,
            exposure: (1 - alpha) * global.exposure + alpha * fitted.exposure,
            noiseArtifacts: (1 - alpha) * global.noiseArtifacts + alpha * fitted.noiseArtifacts,
            resolution: (1 - alpha) * global.resolution + alpha * fitted.resolution
        )
    }

    /// Projects `weights` onto the feasible set for a personalized vector: a
    /// genuine Euclidean projection onto the intersection of a box and the
    /// sum-to-one hyperplane, not the old clamp-then-renormalize
    /// approximation. Clamping into `[g - 0.15, g + 0.15]` and then
    /// renormalizing to sum to 1 can push a component back outside the box
    /// the clamp just enforced — renormalizing rescales every component,
    /// including ones already sitting on their boundary — and two such
    /// passes still do not guarantee both constraints hold simultaneously.
    ///
    /// The box for each component is `[max(g - 0.15, 0), g + 0.15]`, except
    /// `resolution`'s upper bound is additionally capped at
    /// `resolutionWeightCap`: `BestShotRanker` always scores with
    /// `min(weights.resolution, config.resolutionWeightCap)`, so a fitted
    /// weight above the cap would only take normalization mass away from the
    /// other components without the ranker ever spending it — the deployed
    /// score would differ from the fitted one for no benefit. Capping it
    /// here means the raw fitted weight already is the effective weight the
    /// ranker consumes.
    ///
    /// `pinFaceQualityToZero` folds the "faceless cluster" constraint into
    /// the same solve by collapsing that component's box to the single point
    /// 0, rather than pinning and renormalizing afterward — which could push
    /// `resolution` back over its cap the same way clamp-then-renormalize
    /// did, since renormalizing after removing `faceQuality`'s mass scales
    /// every remaining component up.
    ///
    /// The projection itself solves for a single shift `tau`, applied before
    /// clamping, such that `x_i = clip(v_i - tau, lower_i, upper_i)` sums to
    /// 1. `components(shift:).total` is continuous and, in `tau`,
    /// non-increasing (each clipped component is individually non-increasing
    /// in `tau`), and the bracket below is built so the sum is >= 1 at its low end and <= 1
    /// at its high end whenever the box itself is feasible (`lower.total <=
    /// 1 <= upper.total`). Bisection on that bracket therefore converges
    /// monotonically to the unique root — see `projectionBisectionSteps` for
    /// why a fixed count suffices.
    private static func project(
        _ weights: PhotoQualityScoringConfig.Weights,
        global: PhotoQualityScoringConfig.Weights,
        resolutionWeightCap: Double,
        pinFaceQualityToZero: Bool
    ) -> PhotoQualityScoringConfig.Weights? {
        func lowerBound(_ globalValue: Double) -> Double { max(globalValue - boxRadius, 0) }
        func upperBound(_ globalValue: Double) -> Double { globalValue + boxRadius }

        let lower = Vector5(
            sharpness: lowerBound(global.sharpness),
            faceQuality: pinFaceQualityToZero ? 0 : lowerBound(global.faceQuality),
            exposure: lowerBound(global.exposure),
            noiseArtifacts: lowerBound(global.noiseArtifacts),
            resolution: lowerBound(global.resolution)
        )
        let upper = Vector5(
            sharpness: upperBound(global.sharpness),
            faceQuality: pinFaceQualityToZero ? 0 : upperBound(global.faceQuality),
            exposure: upperBound(global.exposure),
            noiseArtifacts: upperBound(global.noiseArtifacts),
            resolution: min(upperBound(global.resolution), resolutionWeightCap)
        )

        let v = Vector5(weights)
        guard v.isFinite else { return nil }

        let lowerTotal = lower.total
        let upperTotal = upper.total
        // An infeasible box (the sum-to-one plane misses the box entirely)
        // has no projection; the caller falls back to the global vector.
        guard lowerTotal.isFinite, upperTotal.isFinite, lowerTotal <= 1, upperTotal >= 1 else { return nil }

        func clip(_ value: Double, shift tau: Double, _ lower: Double, _ upper: Double) -> Double {
            min(max(value - tau, lower), upper)
        }

        func components(shift tau: Double) -> Vector5 {
            Vector5(
                sharpness: clip(v.sharpness, shift: tau, lower.sharpness, upper.sharpness),
                faceQuality: clip(v.faceQuality, shift: tau, lower.faceQuality, upper.faceQuality),
                exposure: clip(v.exposure, shift: tau, lower.exposure, upper.exposure),
                noiseArtifacts: clip(v.noiseArtifacts, shift: tau, lower.noiseArtifacts, upper.noiseArtifacts),
                resolution: clip(v.resolution, shift: tau, lower.resolution, upper.resolution)
            )
        }

        // At `loTau` every component is still pinned to its upper bound (so
        // the sum is `upperTotal >= 1`); at `hiTau` every component is
        // pinned to its lower bound (so the sum is `lowerTotal <= 1`).
        let loTau = min(
            v.sharpness - upper.sharpness,
            v.faceQuality - upper.faceQuality,
            v.exposure - upper.exposure,
            v.noiseArtifacts - upper.noiseArtifacts,
            v.resolution - upper.resolution
        )
        let hiTau = max(
            v.sharpness - lower.sharpness,
            v.faceQuality - lower.faceQuality,
            v.exposure - lower.exposure,
            v.noiseArtifacts - lower.noiseArtifacts,
            v.resolution - lower.resolution
        )

        var low = loTau
        var high = hiTau
        for _ in 0..<projectionBisectionSteps {
            let mid = low + (high - low) / 2
            if components(shift: mid).total >= 1 {
                low = mid
            } else {
                high = mid
            }
        }

        let projected = components(shift: low + (high - low) / 2)
        guard projected.isFinite else { return nil }
        return projected.asWeights
    }

    // MARK: - Small vector helper

    /// A plain 5-component vector for the gradient math, kept separate from
    /// `Weights` because intermediate gradient values are not themselves a
    /// valid weight vector (they need not be non-negative or sum to 1).
    private struct Vector5 {
        var sharpness: Double
        var faceQuality: Double
        var exposure: Double
        var noiseArtifacts: Double
        var resolution: Double

        static let zero = Vector5(sharpness: 0, faceQuality: 0, exposure: 0, noiseArtifacts: 0, resolution: 0)

        init(sharpness: Double, faceQuality: Double, exposure: Double, noiseArtifacts: Double, resolution: Double) {
            self.sharpness = sharpness
            self.faceQuality = faceQuality
            self.exposure = exposure
            self.noiseArtifacts = noiseArtifacts
            self.resolution = resolution
        }

        init(_ weights: PhotoQualityScoringConfig.Weights) {
            self.init(
                sharpness: weights.sharpness,
                faceQuality: weights.faceQuality,
                exposure: weights.exposure,
                noiseArtifacts: weights.noiseArtifacts,
                resolution: weights.resolution
            )
        }

        var isFinite: Bool {
            sharpness.isFinite && faceQuality.isFinite && exposure.isFinite
                && noiseArtifacts.isFinite && resolution.isFinite
        }

        var total: Double {
            sharpness + faceQuality + exposure + noiseArtifacts + resolution
        }

        var asWeights: PhotoQualityScoringConfig.Weights {
            PhotoQualityScoringConfig.Weights(
                sharpness: sharpness,
                faceQuality: faceQuality,
                exposure: exposure,
                noiseArtifacts: noiseArtifacts,
                resolution: resolution
            )
        }

        func dot(_ other: Vector5) -> Double {
            sharpness * other.sharpness
                + faceQuality * other.faceQuality
                + exposure * other.exposure
                + noiseArtifacts * other.noiseArtifacts
                + resolution * other.resolution
        }

        func scaled(by factor: Double) -> Vector5 {
            Vector5(
                sharpness: sharpness * factor,
                faceQuality: faceQuality * factor,
                exposure: exposure * factor,
                noiseArtifacts: noiseArtifacts * factor,
                resolution: resolution * factor
            )
        }

        static func + (lhs: Vector5, rhs: Vector5) -> Vector5 {
            Vector5(
                sharpness: lhs.sharpness + rhs.sharpness,
                faceQuality: lhs.faceQuality + rhs.faceQuality,
                exposure: lhs.exposure + rhs.exposure,
                noiseArtifacts: lhs.noiseArtifacts + rhs.noiseArtifacts,
                resolution: lhs.resolution + rhs.resolution
            )
        }

        static func - (lhs: Vector5, rhs: Vector5) -> Vector5 {
            Vector5(
                sharpness: lhs.sharpness - rhs.sharpness,
                faceQuality: lhs.faceQuality - rhs.faceQuality,
                exposure: lhs.exposure - rhs.exposure,
                noiseArtifacts: lhs.noiseArtifacts - rhs.noiseArtifacts,
                resolution: lhs.resolution - rhs.resolution
            )
        }
    }
}
