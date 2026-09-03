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
                subjectLumaStdDev: 0.25,
                noiseEstimate: 0.1,
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
