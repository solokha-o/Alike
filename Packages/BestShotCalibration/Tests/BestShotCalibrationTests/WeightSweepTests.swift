import XCTest
@testable import BestShotCalibration
@testable import Core

final class WeightSweepTests: XCTestCase {
    private let config = PhotoQualityScoringConfig.current

    private func makeCorpus() -> BestShotCalibrationCorpus {
        BestShotCalibrationCorpus(
            exportedAt: Date(timeIntervalSince1970: 0),
            scoringModelVersion: config.scoringModelVersion,
            thumbnailConfigVersion: config.thumbnailConfigVersion,
            entries: [
                BestShotCalibrationCluster(
                    clusterID: "portrait-1",
                    category: .people,
                    candidates: [
                        makeCandidate(
                            "portrait-1-sharp",
                            globalSharpness: 65,
                            subjectSharpness: 62,
                            faceSharpness: 62
                        ),
                        makeCandidate(
                            "portrait-1-soft-face",
                            globalSharpness: 60,
                            subjectSharpness: 15,
                            faceSharpness: 15
                        ),
                    ],
                    humanBestShotID: "portrait-1-sharp"
                ),
                BestShotCalibrationCluster(
                    clusterID: "landscape-1",
                    category: .landscape,
                    candidates: [
                        makeCandidate("landscape-1-sharp", globalSharpness: 70),
                        makeCandidate("landscape-1-blurred", globalSharpness: 14),
                    ],
                    humanBestShotID: "landscape-1-sharp"
                ),
                BestShotCalibrationCluster(
                    clusterID: "landscape-2",
                    category: .landscape,
                    candidates: [
                        makeCandidate("landscape-2-a", globalSharpness: 48),
                        makeCandidate("landscape-2-b", globalSharpness: 44),
                    ],
                    humanBestShotID: "landscape-2-a"
                ),
                BestShotCalibrationCluster(
                    clusterID: "night-1",
                    category: .night,
                    candidates: [
                        makeCandidate("night-1-a", globalSharpness: 30),
                        makeCandidate("night-1-b", globalSharpness: 28),
                    ],
                    humanBestShotID: "night-1-a"
                ),
            ]
        )
    }

    func testSweepIsDeterministicAcrossRuns() {
        let corpus = makeCorpus()
        let first = WeightSweep.run(corpus: corpus, baseline: config)
        let second = WeightSweep.run(corpus: corpus, baseline: config)

        XCTAssertEqual(first.candidateConfig, second.candidateConfig)
        XCTAssertEqual(first.candidateScore, second.candidateScore)

        let firstMetrics = MetricsReport.compute(corpus: corpus, config: first.candidateConfig)
        let secondMetrics = MetricsReport.compute(corpus: corpus, config: second.candidateConfig)
        let firstReport = ReportWriter.render(metrics: firstMetrics, corpus: corpus, warnings: [])
        let secondReport = ReportWriter.render(metrics: secondMetrics, corpus: corpus, warnings: [])
        XCTAssertEqual(firstReport, secondReport)

        let firstSweepReport = ReportWriter.render(sweep: first)
        let secondSweepReport = ReportWriter.render(sweep: second)
        XCTAssertEqual(firstSweepReport, secondSweepReport)
    }

    func testEveryCandidateWeightsSumToOne() {
        let result = WeightSweep.run(corpus: makeCorpus(), baseline: config)

        XCTAssertEqual(result.candidateConfig.weightsWithFaces.total, 1, accuracy: 1e-9)
        XCTAssertEqual(result.candidateConfig.weightsWithoutFaces.total, 1, accuracy: 1e-9)

        for sensitivity in result.sensitivity {
            for sample in sensitivity.samples {
                // The sensitivity grid only varies scalar thresholds, never the
                // weights, so the weight invariant must still hold at every point.
                XCTAssertEqual(
                    result.candidateConfig.weightsWithFaces.total, 1, accuracy: 1e-9,
                    "sensitivity sample for \(sensitivity.parameterName)=\(sample.value)"
                )
            }
        }
    }

    func testSweepWinnerIsAtLeastAsGoodAsBaseline() {
        let corpus = makeCorpus()
        let result = WeightSweep.run(corpus: corpus, baseline: config)
        let baselineObjective = WeightSweep.score(config: config, corpus: corpus).objective

        XCTAssertGreaterThanOrEqual(result.candidateScore.objective, baselineObjective - 1e-9)
        XCTAssertEqual(result.baselineScore.objective, baselineObjective, accuracy: 1e-9)
    }

    func testBlurPenaltyIsCarriedIntoTheResult() {
        let result = WeightSweep.run(corpus: makeCorpus(), baseline: config, blurPenalty: 3.5)
        XCTAssertEqual(result.blurPenalty, 3.5)
    }

    /// Regression test for the "refuse to answer more often" trap: a synthetic
    /// corpus of 4 clusters, 2 the ranker always gets right (well above any
    /// sharpness floor in play) and 2 it always gets wrong (a close
    /// disagreement, sharper candidate wins, human picked the softer one).
    /// A stricter `absoluteSharpnessFloor` (14 vs. 10) pushes the 2
    /// wrong-and-close clusters into `.unresolved` without the ranker having
    /// gotten anything more right — `correctClusterCount` stays at 2 of 4
    /// either way.
    ///
    /// `topOneAgreement` (over resolved clusters only) predictably rises,
    /// since the clusters that leave its denominator were the wrong ones —
    /// this is the trap `WeightSweep.score` must not fall into.
    /// `topOneAgreementOverAllClusters`, and therefore `objective`, must NOT
    /// improve, because refusing to answer never pays.
    func testStricterFloorDoesNotImproveObjectiveEvenThoughResolvedOnlyAgreementRises() {
        let lenientConfig = PhotoQualityScoringConfig(absoluteSharpnessFloor: 10)
        let strictConfig = PhotoQualityScoringConfig(absoluteSharpnessFloor: 14)

        let corpus = BestShotCalibrationCorpus(
            exportedAt: Date(timeIntervalSince1970: 0),
            scoringModelVersion: lenientConfig.scoringModelVersion,
            thumbnailConfigVersion: lenientConfig.thumbnailConfigVersion,
            entries: [
                makeCluster(id: "correct-1", sharp: 60, soft: 55, humanPicksSharp: true),
                makeCluster(id: "correct-2", sharp: 62, soft: 58, humanPicksSharp: true),
                // Winner (13) sits between the two floors: resolved and WRONG
                // under the lenient floor, unresolved under the strict one.
                makeCluster(id: "borderline-1", sharp: 13, soft: 11, humanPicksSharp: false),
                makeCluster(id: "borderline-2", sharp: 13.5, soft: 11.5, humanPicksSharp: false),
            ]
        )

        let lenientMetrics = MetricsReport.compute(corpus: corpus, config: lenientConfig).overall
        let strictMetrics = MetricsReport.compute(corpus: corpus, config: strictConfig).overall

        // Sanity check on the setup: the strict config really does resolve
        // fewer clusters while getting the exact same number right.
        XCTAssertEqual(lenientMetrics.resolvedClusterCount, 4)
        XCTAssertEqual(strictMetrics.resolvedClusterCount, 2)
        XCTAssertEqual(lenientMetrics.correctClusterCount, 2)
        XCTAssertEqual(strictMetrics.correctClusterCount, 2)

        // The trap: naively scoring on the resolved-only figure would call the
        // stricter config a strict improvement.
        XCTAssertGreaterThan(
            strictMetrics.topOneAgreement ?? -1,
            lenientMetrics.topOneAgreement ?? -1,
            "resolved-only agreement rises purely from shrinking the denominator"
        )

        let lenientScore = WeightSweep.score(config: lenientConfig, corpus: corpus)
        let strictScore = WeightSweep.score(config: strictConfig, corpus: corpus)

        XCTAssertEqual(lenientScore.topOneAgreementOverAllClusters, 0.5, accuracy: 1e-9)
        XCTAssertEqual(strictScore.topOneAgreementOverAllClusters, 0.5, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(
            strictScore.objective,
            lenientScore.objective + 1e-9,
            "refusing to answer more often must never raise the sweep objective"
        )
    }

    /// Regression test for A1: an all-`.unresolved` config must never beat a
    /// config that actually answers, even when some of its winners are
    /// blurry. Under the old formula (`objective = topOneAgreementOverAllClusters
    /// - blurPenalty * blurryWinnerRate`), the refusing config scores exactly
    /// 0 (both terms coerce `nil` to 0), while the answering config's
    /// objective goes negative once the blur penalty on its blurry winners
    /// outweighs its agreement — so refusal would "win". The fix charges an
    /// unresolved cluster into the penalty term at the same rate as a blurry
    /// winner, so refusing can never come out ahead of answering.
    func testAllUnresolvedConfigScoresStrictlyBelowAnAnsweringConfigWithBlurryWinners() {
        // Every candidate sits under both this config's critical sharpness
        // ratio and its absolute floor, so BestShotRanker.decide refuses
        // every cluster: every winner it would otherwise pick is disqualified
        // as blurry, leaving `.unresolved`.
        let refusingConfig = PhotoQualityScoringConfig(
            absoluteSharpnessFloor: 1_000,
            criticalSharpnessRatio: 0.99
        )
        // The shipped default resolves and correctly picks every cluster
        // below, with no blurry winners — a zero-penalty, full-agreement
        // score. Even that must still beat outright refusal.
        let answeringConfig = config

        let corpus = BestShotCalibrationCorpus(
            exportedAt: Date(timeIntervalSince1970: 0),
            scoringModelVersion: answeringConfig.scoringModelVersion,
            thumbnailConfigVersion: answeringConfig.thumbnailConfigVersion,
            entries: [
                makeCluster(id: "c1", sharp: 60, soft: 55, humanPicksSharp: true),
                makeCluster(id: "c2", sharp: 62, soft: 58, humanPicksSharp: true),
                makeCluster(id: "c3", sharp: 70, soft: 65, humanPicksSharp: true),
                makeCluster(id: "c4", sharp: 80, soft: 75, humanPicksSharp: true),
            ]
        )

        let refusingMetrics = MetricsReport.compute(corpus: corpus, config: refusingConfig).overall
        XCTAssertEqual(refusingMetrics.unresolvedCount, refusingMetrics.clusterCount, "setup: every cluster must refuse")

        let refusingScore = WeightSweep.score(config: refusingConfig, corpus: corpus, blurPenalty: 5.0)
        let answeringScore = WeightSweep.score(config: answeringConfig, corpus: corpus, blurPenalty: 5.0)

        // Under the OLD formula this would be exactly 0 (both `nil`-coerced
        // terms vanish). Under the fix, an all-unresolved config is charged
        // the full blur penalty on every cluster: 0 agreement -
        // blurPenalty * (0 blurry winners + 4 unresolved) / 4 clusters == -blurPenalty.
        XCTAssertEqual(refusingScore.objective, -5.0, accuracy: 1e-9, "refusing every cluster is charged the full blur penalty")
        XCTAssertGreaterThan(
            answeringScore.objective,
            refusingScore.objective,
            "a config that answers correctly and unblurred must strictly beat one that refuses everything"
        )
    }

    /// Pins the exact arithmetic of the new objective on a mixed corpus: 2
    /// correct-and-sharp clusters, 1 cluster whose winner is clearly blurry
    /// by the ranker's own definition (below `absoluteSharpnessFloor`) yet
    /// still resolved because a sharper sibling in the same cluster clears
    /// the floor, and 1 cluster where nothing clears the floor at all
    /// (`.unresolved`).
    ///
    /// `topOneAgreementOverAllClusters = correctClusterCount / clusterCount`;
    /// `penalizedBlurryRate = (blurryWinnerCount + unresolvedCount) /
    /// clusterCount`. The exact counts are read off the real
    /// `MetricsReport.Bucket` (with sanity assertions that the corpus really
    /// is mixed — 1 blurry winner, 1 unresolved, neither zero) rather than
    /// hand-guessed, since `BestShotRanker`'s winner selection is not a
    /// simple function of a single candidate's sharpness value.
    func testObjectivePinsExactArithmeticOnAMixedCorpus() {
        let mixedConfig = config

        let corpus = BestShotCalibrationCorpus(
            exportedAt: Date(timeIntervalSince1970: 0),
            scoringModelVersion: mixedConfig.scoringModelVersion,
            thumbnailConfigVersion: mixedConfig.thumbnailConfigVersion,
            entries: [
                // Correct, sharp, resolved.
                makeCluster(id: "correct-1", sharp: 60, soft: 55, humanPicksSharp: true),
                makeCluster(id: "correct-2", sharp: 62, soft: 58, humanPicksSharp: true),
                // 3-candidate cluster designed so the winner sits below the
                // absolute sharpness floor (10) while a sharper sibling
                // clears it — resolved, but a blurry winner. The winner's
                // clean exposure and low noise outweigh its sharpness
                // deficit against the sharper-but-noisy, badly-exposed
                // sibling; the human agrees with the (blurry) winner.
                makeBlurryWinnerCluster(),
                // Both candidates well under the floor: BestShotRanker
                // refuses outright (`.unresolved`).
                makeCluster(id: "unresolved", sharp: 5, soft: 4, humanPicksSharp: true),
            ]
        )

        let metrics = MetricsReport.compute(corpus: corpus, config: mixedConfig).overall
        XCTAssertEqual(metrics.clusterCount, 4)
        XCTAssertGreaterThan(metrics.blurryWinnerCount, 0, "setup: the designed cluster must produce a blurry winner")
        XCTAssertGreaterThan(metrics.unresolvedCount, 0, "setup: the last cluster must refuse outright")

        let score = WeightSweep.score(config: mixedConfig, corpus: corpus, blurPenalty: 5.0)

        let expectedAgreement = Double(metrics.correctClusterCount) / Double(metrics.clusterCount)
        let expectedPenalizedRate = Double(metrics.blurryWinnerCount + metrics.unresolvedCount) / Double(metrics.clusterCount)
        let expectedObjective = expectedAgreement - 5.0 * expectedPenalizedRate

        XCTAssertEqual(score.topOneAgreementOverAllClusters, expectedAgreement, accuracy: 1e-9)
        XCTAssertEqual(score.penalizedBlurryRate, expectedPenalizedRate, accuracy: 1e-9)
        XCTAssertEqual(score.objective, expectedObjective, accuracy: 1e-9)
    }

    /// A cluster whose ranked winner ("clean-but-soft") sits below the
    /// default `absoluteSharpnessFloor` (10) while "sharp-but-dirty" (which
    /// clears the floor) loses on the weighted score despite being sharper,
    /// because its heavy clipping, noise, and low resolution outweigh
    /// `sharpness`'s 0.55 weight once a third candidate ("filler") softens
    /// the sharpness normalization range. Verified against the live
    /// `BestShotRanker`: this resolves to `winnerID` with `.automatic`
    /// confidence (topScore 0.633, margin 0.083). The human label agrees
    /// with the ranker's actual (blurry) pick, so this cluster counts as
    /// "correct" for `topOneAgreementOverAllClusters` while still counting
    /// as a blurry winner.
    private func makeBlurryWinnerCluster() -> BestShotCalibrationCluster {
        let winnerID = "blurry-winner-clean-but-soft"
        let rivalID = "blurry-winner-sharp-but-dirty"
        let fillerID = "blurry-winner-filler"
        return BestShotCalibrationCluster(
            clusterID: "blurry-winner",
            category: nil,
            candidates: [
                makeCandidate(
                    rivalID,
                    globalSharpness: 11,
                    darkClippedFraction: 0.20,
                    noiseEstimate: 0.9,
                    pixelWidth: 2000,
                    pixelHeight: 1500
                ),
                makeCandidate(
                    winnerID,
                    globalSharpness: 9,
                    darkClippedFraction: 0,
                    noiseEstimate: 0.01,
                    pixelWidth: 8000,
                    pixelHeight: 6000
                ),
                makeCandidate(
                    fillerID,
                    globalSharpness: 8,
                    darkClippedFraction: 0,
                    noiseEstimate: 0.5
                ),
            ],
            humanBestShotID: winnerID
        )
    }

    // MARK: - Helpers

    /// A 2-candidate cluster: one sharper photo, one softer one. `humanPicksSharp`
    /// controls whether the human label agrees with what the ranker (which
    /// always prefers the sharper photo here) will pick, so the cluster is
    /// either an easy agreement or a guaranteed disagreement.
    private func makeCluster(
        id: String,
        sharp: Double,
        soft: Double,
        humanPicksSharp: Bool
    ) -> BestShotCalibrationCluster {
        let sharpID = "\(id)-sharp"
        let softID = "\(id)-soft"
        return BestShotCalibrationCluster(
            clusterID: id,
            category: nil,
            candidates: [
                makeCandidate(sharpID, globalSharpness: sharp),
                makeCandidate(softID, globalSharpness: soft),
            ],
            humanBestShotID: humanPicksSharp ? sharpID : softID
        )
    }

    private func makeCandidate(
        _ assetID: String,
        globalSharpness: Double,
        subjectSharpness: Double? = nil,
        faceSharpness: Double? = nil,
        darkClippedFraction: Double = 0,
        noiseEstimate: Double = 0.1,
        pixelWidth: Int = 4000,
        pixelHeight: Int = 3000
    ) -> BestShotCalibrationCandidate {
        let faces: [FaceQualitySignal]? = faceSharpness.map {
            [FaceQualitySignal(
                detectionConfidence: 0.9,
                boxPixelSize: 120,
                sharpness: $0,
                hasClosedEyes: false,
                isCroppedByFrame: false
            )]
        }
        return BestShotCalibrationCandidate(
            assetID: assetID,
            signals: PhotoQualitySignals(
                globalSharpness: globalSharpness,
                subjectSharpness: subjectSharpness,
                darkClippedFraction: darkClippedFraction,
                subjectLumaStdDev: 0.25,
                noiseEstimate: noiseEstimate,
                faceSignals: faces,
                pixelArea: Int64(pixelWidth * pixelHeight)
            ),
            creationDate: Date(timeIntervalSince1970: 1_000),
            modificationDate: Date(timeIntervalSince1970: 1_000),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }
}
