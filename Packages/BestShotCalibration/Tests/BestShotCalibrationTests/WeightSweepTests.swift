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

    // MARK: - Helpers

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
