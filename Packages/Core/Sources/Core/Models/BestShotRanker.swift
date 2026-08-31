import Foundation

/// Ranks the photos of one cluster by measured technical quality.
///
/// A pure, deterministic function: the same snapshots and the same signals
/// always produce the same decision, which is what makes a rescan of an
/// unchanged cluster keep its Best Shot.
///
/// The metadata-only `PhotoClusterBestShot` stays in place as the fallback for
/// everything that runs before analysis has any signals to offer.
public enum BestShotRanker {
    /// Per-candidate breakdown, kept internal: the UI only ever sees the
    /// decision and its reason codes.
    struct Components: Equatable {
        var sharpness: Double
        var exposure: Double
        var noise: Double
        var faceQuality: Double
        var resolution: Double
        var penalty: Double
        var favoriteBonus: Double
        var hasCriticalBlur: Bool
        var hasCriticalExposure: Bool
        var hasClosedEyes: Bool
        var isFavorite: Bool
        var score: Double
    }

    public static func decide(
        snapshots: [PhotoClusterAssetSnapshot],
        scores: [String: PhotoQualityScore],
        config: PhotoQualityScoringConfig = .current
    ) -> BestShotDecision {
        guard !snapshots.isEmpty else { return .empty }

        let usable = snapshots.filter { scores[$0.localIdentifier]?.signals.isUsable == true }
        guard usable.count > 1 else {
            return singleOrMetadataDecision(snapshots: snapshots, scores: scores)
        }

        let signals = usable.reduce(into: [String: PhotoQualitySignals]()) { partial, snapshot in
            partial[snapshot.localIdentifier] = scores[snapshot.localIdentifier]?.signals
        }

        // 1. Sharpness relative to the cluster, then the exclusion rule.
        let effectiveSharpness = usable.reduce(into: [String: Double]()) { partial, snapshot in
            partial[snapshot.localIdentifier] = self.effectiveSharpness(
                of: signals[snapshot.localIdentifier] ?? PhotoQualitySignals(),
                config: config
            )
        }
        let medianSharpness = median(effectiveSharpness.values.sorted())
        let sharpnessRatios = effectiveSharpness.mapValues { value -> Double in
            guard medianSharpness > 0 else { return 1 }
            return value / medianSharpness
        }
        let hasSharpReference = sharpnessRatios.values.contains { $0 >= config.referenceSharpnessRatio }
        var excluded = Set<String>()
        if hasSharpReference {
            for snapshot in usable
            where (sharpnessRatios[snapshot.localIdentifier] ?? 1) < config.criticalSharpnessRatio {
                excluded.insert(snapshot.localIdentifier)
            }
        }
        // Never empty the cluster: if everything is weak, keep them all and let
        // the confidence gate say so instead of hiding photos.
        if excluded.count == usable.count { excluded.removeAll() }

        let ranked = usable.filter { !excluded.contains($0.localIdentifier) }

        // 2. Robust normalization inside the cluster.
        let sharpnessScale = NormalizationScale(
            values: ranked.compactMap { effectiveSharpness[$0.localIdentifier] },
            config: config
        )
        let noiseScale = NormalizationScale(
            values: ranked.compactMap { signals[$0.localIdentifier]?.noiseEstimate },
            config: config
        )
        let faceSharpnessScale = NormalizationScale(
            values: ranked.flatMap { snapshot in
                (signals[snapshot.localIdentifier]?.usableFaceSignals ?? []).map(\.sharpness)
            },
            config: config
        )
        let resolutionScale = NormalizationScale(
            values: ranked.map { Double($0.pixelArea) }.map { area in area > 0 ? log(area) : 0 },
            config: config
        )
        let clusterHasFaces = ranked.contains { signals[$0.localIdentifier]?.hasFaces == true }
        let weights = clusterHasFaces ? config.weightsWithFaces : config.weightsWithoutFaces

        // 3. Components and the weighted sum.
        var components: [String: Components] = [:]
        for snapshot in ranked {
            let signal = signals[snapshot.localIdentifier] ?? PhotoQualitySignals()
            components[snapshot.localIdentifier] = makeComponents(
                snapshot: snapshot,
                signals: signal,
                sharpnessRatio: sharpnessRatios[snapshot.localIdentifier] ?? 1,
                sharpnessScale: sharpnessScale,
                noiseScale: noiseScale,
                faceSharpnessScale: faceSharpnessScale,
                resolutionScale: resolutionScale,
                clusterHasFaces: clusterHasFaces,
                weights: weights,
                config: config
            )
        }

        // 4. Deterministic order.
        let order = ranked.sorted { lhs, rhs in
            isRankedAhead(lhs, rhs, components: components, config: config)
        }
        let rankedCandidates = order.map { snapshot in
            BestShotCandidate(
                localIdentifier: snapshot.localIdentifier,
                score: components[snapshot.localIdentifier]?.score ?? 0,
                isExcluded: false,
                hasQualitySignals: true
            )
        } + excludedCandidates(excluded, snapshots: snapshots)

        guard let winner = order.first else {
            return singleOrMetadataDecision(snapshots: snapshots, scores: scores)
        }
        let topScore = components[winner.localIdentifier]?.score ?? 0
        let runnerUpScore = order.dropFirst().first.flatMap { components[$0.localIdentifier]?.score } ?? 0
        let margin = order.count > 1 ? max(0, topScore - runnerUpScore) : 1

        // 5. Confidence gate. Incomplete coverage never claims certainty.
        let hasCompleteCoverage = snapshots.allSatisfy { scores[$0.localIdentifier] != nil }
        // An absolute floor on top of the relative ranking: when every frame is
        // weak, the least blurred one is still not a Best Shot.
        let reachesAbsoluteFloor = ranked.contains { snapshot in
            (effectiveSharpness[snapshot.localIdentifier] ?? 0) >= config.absoluteSharpnessFloor
        }
        let confidence: BestShotConfidence
        if !reachesAbsoluteFloor {
            confidence = .unresolved
        } else if topScore >= config.automaticSelectionMinimumScore, margin >= config.automaticSelectionMinimumMargin {
            confidence = hasCompleteCoverage ? .automatic : .lowConfidence
        } else if margin >= config.lowConfidenceMinimumMargin {
            confidence = .lowConfidence
        } else {
            confidence = .unresolved
        }

        let reasonCodes: [BestShotReasonCode]
        if confidence == .unresolved {
            reasonCodes = []
        } else if order.count == 1, !excluded.isEmpty {
            // The only rivals were dropped for critical blur, which is exactly
            // what the badge should say.
            reasonCodes = [.sharper]
        } else {
            reasonCodes = self.reasonCodes(
                winner: components[winner.localIdentifier],
                runnerUp: order.dropFirst().first.flatMap { components[$0.localIdentifier] },
                weights: weights,
                config: config
            )
        }

        return BestShotDecision(
            localIdentifier: confidence == .unresolved ? nil : winner.localIdentifier,
            confidence: confidence,
            topScore: topScore,
            margin: margin,
            reasonCodes: reasonCodes,
            rankedCandidates: rankedCandidates
        )
    }

    // MARK: - Fallbacks

    /// Nothing measured, or only one measured photo: behave exactly like the
    /// metadata-only ranking the app already shipped, rather than inventing a
    /// confidence level out of a single reading.
    private static func singleOrMetadataDecision(
        snapshots: [PhotoClusterAssetSnapshot],
        scores: [String: PhotoQualityScore]
    ) -> BestShotDecision {
        let ordered = snapshots.sorted { lhs, rhs in
            PhotoClusterBestShot.isPreferredAsset(rhs, lhs)
        }
        return BestShotDecision(
            localIdentifier: ordered.first?.localIdentifier,
            confidence: .automatic,
            topScore: 0,
            margin: 0,
            reasonCodes: [],
            rankedCandidates: ordered.map { snapshot in
                BestShotCandidate(
                    localIdentifier: snapshot.localIdentifier,
                    score: 0,
                    isExcluded: false,
                    hasQualitySignals: scores[snapshot.localIdentifier]?.signals.isUsable == true
                )
            }
        )
    }

    private static func excludedCandidates(
        _ excluded: Set<String>,
        snapshots: [PhotoClusterAssetSnapshot]
    ) -> [BestShotCandidate] {
        snapshots
            .filter { excluded.contains($0.localIdentifier) }
            .map { snapshot in
                BestShotCandidate(
                    localIdentifier: snapshot.localIdentifier,
                    score: 0,
                    isExcluded: true,
                    hasQualitySignals: true
                )
            }
    }

    // MARK: - Components

    private static func effectiveSharpness(
        of signals: PhotoQualitySignals,
        config: PhotoQualityScoringConfig
    ) -> Double {
        guard let subject = signals.subjectSharpness else { return signals.globalSharpness }
        return config.subjectSharpnessWeight * subject
            + (1 - config.subjectSharpnessWeight) * signals.globalSharpness
    }

    private static func makeComponents(
        snapshot: PhotoClusterAssetSnapshot,
        signals: PhotoQualitySignals,
        sharpnessRatio: Double,
        sharpnessScale: NormalizationScale,
        noiseScale: NormalizationScale,
        faceSharpnessScale: NormalizationScale,
        resolutionScale: NormalizationScale,
        clusterHasFaces: Bool,
        weights: PhotoQualityScoringConfig.Weights,
        config: PhotoQualityScoringConfig
    ) -> Components {
        let sharpness = sharpnessScale.normalize(effectiveSharpness(of: signals, config: config))
        let noise = 1 - noiseScale.normalize(signals.noiseEstimate)
        let exposure = exposureComponent(signals: signals, config: config)
        let resolution = resolutionScale.normalize(
            snapshot.pixelArea > 0 ? log(Double(snapshot.pixelArea)) : 0
        )

        let faces = signals.usableFaceSignals
        let faceQuality: Double
        if !clusterHasFaces {
            faceQuality = 0
        } else if faces.isEmpty {
            faceQuality = config.neutralComponentScore
        } else {
            let qualities = faces.map { faceSharpnessScale.normalize($0.sharpness) }
            let worst = qualities.min() ?? 0
            let average = qualities.reduce(0, +) / Double(qualities.count)
            faceQuality = config.worstFaceWeight * worst + (1 - config.worstFaceWeight) * average
        }

        var penalty = sharpnessPenalty(ratio: sharpnessRatio, config: config)
        if clusterHasFaces {
            penalty += facePenalty(faces: faces, faceSharpnessScale: faceSharpnessScale, config: config)
        }
        if signals.subjectLumaStdDev < config.lowContrastStdDev {
            penalty += config.lowContrastPenalty
        }

        let hasCriticalBlur = sharpnessRatio < config.criticalSharpnessRatio
        let hasCriticalExposure = signals.clippedFraction > config.clippingCriticalFraction
        let favoriteBonus = snapshot.isFavorite && !hasCriticalBlur && !hasCriticalExposure
            ? config.favoriteBonus
            : 0

        let weighted = weights.sharpness * sharpness
            + weights.faceQuality * faceQuality
            + weights.exposure * exposure
            + weights.noiseArtifacts * noise
            + min(weights.resolution, config.resolutionWeightCap) * resolution

        return Components(
            sharpness: sharpness,
            exposure: exposure,
            noise: noise,
            faceQuality: faceQuality,
            resolution: resolution,
            penalty: penalty,
            favoriteBonus: favoriteBonus,
            hasCriticalBlur: hasCriticalBlur,
            hasCriticalExposure: hasCriticalExposure,
            hasClosedEyes: faces.contains { $0.hasClosedEyes == true },
            isFavorite: snapshot.isFavorite,
            score: min(max(weighted - penalty + favoriteBonus, 0), 1)
        )
    }

    private static func exposureComponent(
        signals: PhotoQualitySignals,
        config: PhotoQualityScoringConfig
    ) -> Double {
        let clipped = signals.clippedFraction
        guard clipped > config.clippingFreeFraction else { return 1 }
        let span = max(config.clippingFullPenaltyFraction - config.clippingFreeFraction, .ulpOfOne)
        let ramp = (clipped - config.clippingFreeFraction) / span
        return min(max(1 - ramp, 0), 1)
    }

    private static func sharpnessPenalty(
        ratio: Double,
        config: PhotoQualityScoringConfig
    ) -> Double {
        if ratio < config.criticalSharpnessRatio { return config.criticalSharpnessPenalty }
        if ratio < config.strongPenaltySharpnessRatio { return config.strongSharpnessPenalty }
        if ratio < config.weakPenaltySharpnessRatio { return config.weakSharpnessPenalty }
        return 0
    }

    private static func facePenalty(
        faces: [FaceQualitySignal],
        faceSharpnessScale: NormalizationScale,
        config: PhotoQualityScoringConfig
    ) -> Double {
        guard !faces.isEmpty else { return 0 }
        var penalty: Double = 0
        let isMainFaceUnusable = faces.contains { face in
            face.isCroppedByFrame || faceSharpnessScale.normalize(face.sharpness) < 0.5
        }
        if isMainFaceUnusable {
            penalty += config.croppedOrBlurredFacePenalty
        }
        if faces.contains(where: { $0.hasClosedEyes == true }) {
            penalty += config.closedEyesPenalty
        }
        return penalty
    }

    // MARK: - Ordering

    private static func isRankedAhead(
        _ lhs: PhotoClusterAssetSnapshot,
        _ rhs: PhotoClusterAssetSnapshot,
        components: [String: Components],
        config: PhotoQualityScoringConfig
    ) -> Bool {
        let lhsScore = components[lhs.localIdentifier]?.score ?? 0
        let rhsScore = components[rhs.localIdentifier]?.score ?? 0
        if abs(lhsScore - rhsScore) > config.scoreEqualityTolerance {
            return lhsScore > rhsScore
        }

        let lhsCreation = lhs.creationDate?.timeIntervalSince1970 ?? 0
        let rhsCreation = rhs.creationDate?.timeIntervalSince1970 ?? 0
        if lhsCreation != rhsCreation { return lhsCreation > rhsCreation }

        let lhsModification = lhs.modificationDate?.timeIntervalSince1970 ?? 0
        let rhsModification = rhs.modificationDate?.timeIntervalSince1970 ?? 0
        if lhsModification != rhsModification { return lhsModification > rhsModification }

        return lhs.localIdentifier < rhs.localIdentifier
    }

    // MARK: - Reason codes

    private static func reasonCodes(
        winner: Components?,
        runnerUp: Components?,
        weights: PhotoQualityScoringConfig.Weights,
        config: PhotoQualityScoringConfig
    ) -> [BestShotReasonCode] {
        guard let winner else { return [] }
        guard let runnerUp else { return [] }

        var weighted: [(BestShotReasonCode, Double)] = [
            (.sharper, weights.sharpness * (winner.sharpness - runnerUp.sharpness)
                + (runnerUp.penalty - winner.penalty)),
            (.betterExposure, weights.exposure * (winner.exposure - runnerUp.exposure)),
            (.faceInFocus, weights.faceQuality * (winner.faceQuality - runnerUp.faceQuality)),
            (.lessNoise, weights.noiseArtifacts * (winner.noise - runnerUp.noise)),
            (.higherResolution, min(weights.resolution, config.resolutionWeightCap)
                * (winner.resolution - runnerUp.resolution))
        ]
        if !winner.hasClosedEyes, runnerUp.hasClosedEyes {
            weighted.append((.openEyes, config.closedEyesPenalty))
        }
        if winner.isFavorite, !runnerUp.isFavorite, winner.favoriteBonus > 0 {
            weighted.append((.favorite, winner.favoriteBonus))
        }

        return weighted
            .filter { $0.1 >= config.reasonCodeMinimumDelta }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1
                    ? lhs.0.rawValue < rhs.0.rawValue
                    : lhs.1 > rhs.1
            }
            .prefix(3)
            .map(\.0)
    }

    // MARK: - Math helpers

    /// Robust P10…P90 scale, so one outlier frame cannot squash the range.
    struct NormalizationScale {
        let low: Double
        let high: Double
        let neutralValue: Double

        init(values: [Double], config: PhotoQualityScoringConfig) {
            neutralValue = config.neutralComponentScore
            let sorted = values.filter(\.isFinite).sorted()
            guard !sorted.isEmpty else {
                low = 0
                high = 0
                return
            }
            low = BestShotRanker.percentile(sorted, config.normalizationLowPercentile)
            high = BestShotRanker.percentile(sorted, config.normalizationHighPercentile)
        }

        func normalize(_ value: Double) -> Double {
            guard value.isFinite else { return 0 }
            // Nothing to compare against inside this cluster: stay neutral
            // instead of handing every candidate a perfect or a zero component.
            guard high - low > .ulpOfOne else { return neutralValue }
            return min(max((value - low) / (high - low), 0), 1)
        }
    }

    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let position = fraction * Double(sorted.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(lowerIndex + 1, sorted.count - 1)
        let weight = position - Double(lowerIndex)
        return sorted[lowerIndex] * (1 - weight) + sorted[upperIndex] * weight
    }

    static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
