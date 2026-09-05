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
        /// Penalty from the sharpness bands alone.
        var sharpnessPenalty: Double
        /// Penalty from a cropped or soft main face.
        var facePenalty: Double
        /// Penalty from confirmed closed eyes.
        var closedEyesPenalty: Double
        /// Penalty from a flat, contrastless subject.
        var contrastPenalty: Double
        var favoriteBonus: Double
        var hasCriticalBlur: Bool
        var hasCriticalExposure: Bool
        var hasClosedEyes: Bool
        var isFavorite: Bool
        var score: Double

        var penalty: Double { sharpnessPenalty + facePenalty + closedEyesPenalty + contrastPenalty }
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

        let built = rankedComponents(snapshots: snapshots, scores: scores, config: config)
        let signals = built.signals
        let excluded = built.excluded
        let ranked = built.ranked
        let components = built.components
        let weights = built.weights

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

        // 5. Confidence gate. Incomplete coverage never claims certainty, and a
        // candidate whose analysis failed is not covered just because a row
        // exists for it — the row says "unknown", not "measured".
        let hasCompleteCoverage = snapshots.allSatisfy {
            scores[$0.localIdentifier]?.signals.isUsable == true
        }
        // An absolute floor on top of the relative ranking: when every frame is
        // weak, the least blurred one is still not a Best Shot.
        //
        // Measured on the whole frame, never on the subject blend: the ROI is
        // sampled on its own, larger grid, so a face crop's Laplacian is on a
        // different scale than the floor was calibrated for — comparing the
        // blend against it would call every portrait cluster weak.
        let reachesAbsoluteFloor = ranked.contains { snapshot in
            (signals[snapshot.localIdentifier]?.globalSharpness ?? 0) >= config.absoluteSharpnessFloor
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

    /// Each candidate's sharpness relative to the cluster median, the same
    /// computation `decide` uses to drop a critically blurred frame.
    ///
    /// Public so the offline calibration harness can judge "clearly blurry
    /// winner" against the ranker's own definition instead of a hand-rolled
    /// copy that could quietly drift from it. Unusable candidates (failed
    /// analysis, or anything `scores` has no row for) are filtered out first,
    /// exactly as `decide` filters them before this computation runs, so the
    /// median is never dragged around by a photo that could not be measured.
    public static func sharpnessRatios(
        snapshots: [PhotoClusterAssetSnapshot],
        scores: [String: PhotoQualityScore],
        config: PhotoQualityScoringConfig = .current
    ) -> [String: Double] {
        let usable = snapshots.filter { scores[$0.localIdentifier]?.signals.isUsable == true }
        let effectiveSharpness = usable.reduce(into: [String: Double]()) { partial, snapshot in
            partial[snapshot.localIdentifier] = self.effectiveSharpness(
                of: scores[snapshot.localIdentifier]?.signals ?? PhotoQualitySignals(),
                config: config
            )
        }
        let medianSharpness = median(effectiveSharpness.values.sorted())
        return effectiveSharpness.mapValues { value -> Double in
            guard medianSharpness > 0 else { return 1 }
            return value / medianSharpness
        }
    }

    /// One "chosen vs. recommended" pair from a single cluster, broken down
    /// into the per-component gap between the two frames.
    ///
    /// `decide` only ever surfaces the winner and its reason codes; fitting
    /// personal weights later needs the raw components underneath that
    /// decision, for exactly the two candidates a user compared. This runs
    /// the same normalization and component build `decide` uses — an example
    /// is only meaningful if it was measured on the identical scale the live
    /// ranking used — and reduces it to a delta plus the fixed offset no
    /// weight can move.
    public static func overrideExample(
        snapshots: [PhotoClusterAssetSnapshot],
        scores: [String: PhotoQualityScore],
        chosen: String,
        recommended: String,
        now: Date = Date(),
        config: PhotoQualityScoringConfig = .current
    ) -> BestShotOverrideExample? {
        guard chosen != recommended else { return nil }

        let usable = snapshots.filter { scores[$0.localIdentifier]?.signals.isUsable == true }
        guard usable.count > 1 else { return nil }

        let built = rankedComponents(snapshots: snapshots, scores: scores, config: config)
        // Absent from the snapshots, excluded for critical blur, or simply
        // never measured: `components` only holds an entry for a ranked
        // candidate, so a missing key covers all three at once.
        guard let chosenComponents = built.components[chosen],
              let recommendedComponents = built.components[recommended]
        else { return nil }
        // A score pinned at 0 or 1 no longer obeys `weighted - penalty +
        // bonus`; the pair would teach the fit a relationship that only holds
        // away from the clamp.
        guard chosenComponents.score > 0, chosenComponents.score < 1,
              recommendedComponents.score > 0, recommendedComponents.score < 1
        else { return nil }

        let componentDelta = PhotoQualityScoringConfig.Weights(
            sharpness: chosenComponents.sharpness - recommendedComponents.sharpness,
            faceQuality: chosenComponents.faceQuality - recommendedComponents.faceQuality,
            exposure: chosenComponents.exposure - recommendedComponents.exposure,
            noiseArtifacts: chosenComponents.noise - recommendedComponents.noise,
            resolution: chosenComponents.resolution - recommendedComponents.resolution
        )
        let offsetDelta = (chosenComponents.favoriteBonus - chosenComponents.penalty)
            - (recommendedComponents.favoriteBonus - recommendedComponents.penalty)

        return BestShotOverrideExample(
            recordedAt: now,
            clusterHasFaces: built.clusterHasFaces,
            componentDelta: componentDelta,
            offsetDelta: offsetDelta,
            scoringModelVersion: config.scoringModelVersion
        )
    }

    /// The shared build `decide` and `overrideExample` both need: the
    /// cluster-relative normalization scales, the ranked/excluded split, and
    /// the resulting per-candidate `Components`. Kept as one path so the two
    /// callers can never quietly drift onto different scales.
    private static func rankedComponents(
        snapshots: [PhotoClusterAssetSnapshot],
        scores: [String: PhotoQualityScore],
        config: PhotoQualityScoringConfig
    ) -> (
        signals: [String: PhotoQualitySignals],
        ranked: [PhotoClusterAssetSnapshot],
        excluded: Set<String>,
        clusterHasFaces: Bool,
        weights: PhotoQualityScoringConfig.Weights,
        components: [String: Components]
    ) {
        let usable = snapshots.filter { scores[$0.localIdentifier]?.signals.isUsable == true }
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
        let sharpnessRatios = self.sharpnessRatios(snapshots: usable, scores: scores, config: config)
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

        return (signals, ranked, excluded, clusterHasFaces, weights, components)
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
        // Metadata alone is what the app always did, so a cluster nobody has
        // measured yet keeps its confident badge, and a lone photo is trivially
        // its own Best Shot. Anything in between — some photos measured, some
        // failed, some missing — is partial knowledge the ranking could not
        // use, and the badge says so rather than pretending.
        let isMetadataOnly = snapshots.allSatisfy { scores[$0.localIdentifier] == nil }
        let confidence: BestShotConfidence = snapshots.count == 1 || isMetadataOnly
            ? .automatic
            : .lowConfidence
        return BestShotDecision(
            localIdentifier: ordered.first?.localIdentifier,
            confidence: confidence,
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

        let sharpnessBandPenalty = sharpnessPenalty(ratio: sharpnessRatio, config: config)
        let facePenalties = clusterHasFaces
            ? facePenalty(faces: faces, faceSharpnessScale: faceSharpnessScale, config: config)
            : (face: 0, closedEyes: 0)
        let contrastPenaltyValue = signals.subjectLumaStdDev < config.lowContrastStdDev
            ? config.lowContrastPenalty
            : 0
        let penalty = sharpnessBandPenalty
            + facePenalties.face
            + facePenalties.closedEyes
            + contrastPenaltyValue

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
            sharpnessPenalty: sharpnessBandPenalty,
            facePenalty: facePenalties.face,
            closedEyesPenalty: facePenalties.closedEyes,
            contrastPenalty: contrastPenaltyValue,
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

    /// Split apart, because each half explains a different reason code.
    private static func facePenalty(
        faces: [FaceQualitySignal],
        faceSharpnessScale: NormalizationScale,
        config: PhotoQualityScoringConfig
    ) -> (face: Double, closedEyes: Double) {
        guard !faces.isEmpty else { return (0, 0) }
        let isMainFaceUnusable = faces.contains { face in
            face.isCroppedByFrame || faceSharpnessScale.normalize(face.sharpness) < 0.5
        }
        return (
            isMainFaceUnusable ? config.croppedOrBlurredFacePenalty : 0,
            faces.contains { $0.hasClosedEyes == true } ? config.closedEyesPenalty : 0
        )
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
            // Each code carries only its own component and its own penalty, so
            // "Sharper" never ends up explaining a rival's closed eyes.
            (.sharper, weights.sharpness * (winner.sharpness - runnerUp.sharpness)
                + (runnerUp.sharpnessPenalty - winner.sharpnessPenalty)),
            (.betterExposure, weights.exposure * (winner.exposure - runnerUp.exposure)
                + (runnerUp.contrastPenalty - winner.contrastPenalty)),
            (.faceInFocus, weights.faceQuality * (winner.faceQuality - runnerUp.faceQuality)
                + (runnerUp.facePenalty - winner.facePenalty)),
            (.lessNoise, weights.noiseArtifacts * (winner.noise - runnerUp.noise)),
            (.higherResolution, min(weights.resolution, config.resolutionWeightCap)
                * (winner.resolution - runnerUp.resolution))
        ]
        if !winner.hasClosedEyes, runnerUp.hasClosedEyes {
            weighted.append((.openEyes, runnerUp.closedEyesPenalty - winner.closedEyesPenalty))
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
