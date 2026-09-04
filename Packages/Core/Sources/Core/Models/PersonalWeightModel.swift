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
            pinFaceQualityToZero: false
        )
        let withoutFaces = fitBranch(
            examples: withoutFacesExamples,
            global: global.weightsWithoutFaces,
            pinFaceQualityToZero: true
        )
        return (withFaces, withoutFaces)
    }

    // MARK: - Per-branch fit

    private static func fitBranch(
        examples: [BestShotOverrideExample],
        global: PhotoQualityScoringConfig.Weights,
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

        guard var projected = project(shrunk, global: global) else { return global }

        if pinFaceQualityToZero {
            projected = pinFaceQualityToZeroAndRenormalize(projected)
        }
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

    /// Projects onto the allowed set: clamp into `[g - 0.15, g + 0.15]`,
    /// clamp to >= 0, renormalise to sum to 1 — twice, because renormalising
    /// can push a component back out of the box the first pass just
    /// enforced. Two passes settle it for five components.
    private static func project(
        _ weights: PhotoQualityScoringConfig.Weights,
        global: PhotoQualityScoringConfig.Weights
    ) -> PhotoQualityScoringConfig.Weights? {
        var current = weights
        for _ in 0..<2 {
            guard let normalized = clampAndRenormalize(current, global: global) else { return nil }
            current = normalized
        }
        return current
    }

    private static func clampAndRenormalize(
        _ weights: PhotoQualityScoringConfig.Weights,
        global: PhotoQualityScoringConfig.Weights
    ) -> PhotoQualityScoringConfig.Weights? {
        func clamp(_ value: Double, _ globalValue: Double) -> Double {
            let boxed = min(max(value, globalValue - 0.15), globalValue + 0.15)
            return max(boxed, 0)
        }

        let clamped = PhotoQualityScoringConfig.Weights(
            sharpness: clamp(weights.sharpness, global.sharpness),
            faceQuality: clamp(weights.faceQuality, global.faceQuality),
            exposure: clamp(weights.exposure, global.exposure),
            noiseArtifacts: clamp(weights.noiseArtifacts, global.noiseArtifacts),
            resolution: clamp(weights.resolution, global.resolution)
        )

        let sum = clamped.total
        guard sum.isFinite, sum > 0 else { return nil }
        return PhotoQualityScoringConfig.Weights(
            sharpness: clamped.sharpness / sum,
            faceQuality: clamped.faceQuality / sum,
            exposure: clamped.exposure / sum,
            noiseArtifacts: clamped.noiseArtifacts / sum,
            resolution: clamped.resolution / sum
        )
    }

    /// `faceQuality` is structurally 0 in a faceless cluster, so any weight
    /// the fit put on it is fitting noise, not signal. Pin it to exactly 0
    /// and renormalise the remaining four components to sum to 1.
    private static func pinFaceQualityToZeroAndRenormalize(
        _ weights: PhotoQualityScoringConfig.Weights
    ) -> PhotoQualityScoringConfig.Weights {
        let remainder = weights.sharpness + weights.exposure + weights.noiseArtifacts + weights.resolution
        guard remainder.isFinite, remainder > 0 else {
            return PhotoQualityScoringConfig.Weights(
                sharpness: weights.sharpness,
                faceQuality: 0,
                exposure: weights.exposure,
                noiseArtifacts: weights.noiseArtifacts,
                resolution: weights.resolution
            )
        }
        return PhotoQualityScoringConfig.Weights(
            sharpness: weights.sharpness / remainder,
            faceQuality: 0,
            exposure: weights.exposure / remainder,
            noiseArtifacts: weights.noiseArtifacts / remainder,
            resolution: weights.resolution / remainder
        )
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
