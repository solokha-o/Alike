import XCTest
@testable import BestShotCalibration
@testable import Core

final class MetricsReportTests: XCTestCase {
    private let config = PhotoQualityScoringConfig.current

    /// A synthetic corpus of 4 clusters:
    /// - "obvious": one sharp photo, one badly blurred one; the human picked
    ///   the sharp one, matching what the ranker should pick too.
    /// - "disagreement": the human picked the softer of two decent photos.
    /// - "weak": both candidates fall below the absolute sharpness floor, so
    ///   the ranker comes out `.unresolved`.
    /// - "single": one candidate only, trivially resolved.
    private func makeCorpus() -> BestShotCalibrationCorpus {
        BestShotCalibrationCorpus(
            exportedAt: Date(timeIntervalSince1970: 0),
            scoringModelVersion: config.scoringModelVersion,
            thumbnailConfigVersion: config.thumbnailConfigVersion,
            entries: [
                BestShotCalibrationCluster(
                    clusterID: "obvious",
                    category: .people,
                    candidates: [
                        makeCandidate("obvious-sharp", globalSharpness: 60),
                        makeCandidate("obvious-blurred", globalSharpness: 12),
                    ],
                    humanBestShotID: "obvious-sharp"
                ),
                BestShotCalibrationCluster(
                    clusterID: "disagreement",
                    category: .landscape,
                    candidates: [
                        makeCandidate("disagreement-a", globalSharpness: 55),
                        makeCandidate("disagreement-b", globalSharpness: 50),
                    ],
                    humanBestShotID: "disagreement-b"
                ),
                BestShotCalibrationCluster(
                    clusterID: "weak",
                    category: .night,
                    candidates: [
                        makeCandidate("weak-a", globalSharpness: 4),
                        makeCandidate("weak-b", globalSharpness: 3),
                    ],
                    humanBestShotID: "weak-a"
                ),
                BestShotCalibrationCluster(
                    clusterID: "single",
                    category: nil,
                    candidates: [
                        makeCandidate("single-only", globalSharpness: 45),
                    ],
                    humanBestShotID: "single-only"
                ),
            ]
        )
    }

    func testOverallMetrics() {
        let report = MetricsReport.compute(corpus: makeCorpus(), config: config)
        let overall = report.overall

        XCTAssertEqual(overall.clusterCount, 4)
        XCTAssertEqual(overall.unresolvedCount, 1, "the weak cluster never reaches the absolute sharpness floor")
        XCTAssertEqual(overall.unresolvedRate, 0.25, accuracy: 1e-9)

        // Resolved clusters: obvious, disagreement, single = 3. Agreements: obvious + single = 2.
        XCTAssertEqual(overall.resolvedClusterCount, 3)
        XCTAssertEqual(overall.topOneAgreement ?? -1, 2.0 / 3.0, accuracy: 1e-9)

        // Over ALL 4 clusters, correct picks are still obvious + single = 2; the
        // unresolved "weak" cluster counts as a miss rather than being excluded.
        XCTAssertEqual(overall.correctClusterCount, 2)
        XCTAssertEqual(overall.topOneAgreementOverAllClusters ?? -1, 2.0 / 4.0, accuracy: 1e-9)
        XCTAssertEqual(overall.coverageRate, 0.75, accuracy: 1e-9)

        // No winner is clearly blurry by the ranker's own definition here.
        XCTAssertEqual(overall.winnerClusterCount, 3)
        XCTAssertEqual(overall.blurryWinnerRate ?? -1, 0, accuracy: 1e-9)

        // Override-eligible clusters are automatic/lowConfidence with a winner: obvious, disagreement,
        // and single all resolve to .automatic here, and disagreement is the one that disagrees with
        // the human label, so the offline proxy is 1/3.
        XCTAssertEqual(overall.overrideEligibleClusterCount, 3)
        XCTAssertEqual(overall.offlineOverrideProxy ?? -1, 1.0 / 3.0, accuracy: 1e-9)
    }

    func testUnresolvedClusterHasNoWinner() {
        let report = MetricsReport.compute(corpus: makeCorpus(), config: config)
        // Sanity check on the underlying decision, so the metric above is not
        // trusted blindly.
        let weakCluster = makeCorpus().entries.first { $0.clusterID == "weak" }!
        let decision = BestShotRanker.decide(
            snapshots: weakCluster.snapshots,
            scores: weakCluster.scores(
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion
            ),
            config: config
        )
        XCTAssertEqual(decision.confidence, .unresolved)
        XCTAssertNil(decision.localIdentifier)
        XCTAssertGreaterThanOrEqual(report.overall.unresolvedCount, 1)
    }

    func testPerCategoryBreakdown() {
        let report = MetricsReport.compute(corpus: makeCorpus(), config: config)
        let keys = report.byCategory.map(\.key)

        XCTAssertTrue(keys.contains(.category(.people)))
        XCTAssertTrue(keys.contains(.category(.landscape)))
        XCTAssertTrue(keys.contains(.category(.night)))
        XCTAssertTrue(keys.contains(.uncategorised))

        let people = report.byCategory.first { $0.key == .category(.people) }!.bucket
        XCTAssertEqual(people.clusterCount, 1)
        XCTAssertEqual(people.topOneAgreement ?? -1, 1, accuracy: 1e-9)

        let uncategorised = report.byCategory.first { $0.key == .uncategorised }!.bucket
        XCTAssertEqual(uncategorised.clusterCount, 1)
    }

    func testCategoryOrderIsDeterministic() {
        let first = MetricsReport.compute(corpus: makeCorpus(), config: config)
        let second = MetricsReport.compute(corpus: makeCorpus(), config: config)
        XCTAssertEqual(first.byCategory.map(\.key), second.byCategory.map(\.key))
    }

    // MARK: - Face coverage

    /// The report has to be able to say "we found faces and rejected every one
    /// of them". Without that, a corpus where face scoring never engages reads
    /// exactly like a corpus of landscapes.
    func testFaceCoverageSeparatesRejectedFacesFromPhotosWithNobodyInThem() {
        let corpus = BestShotCalibrationCorpus(
            exportedAt: Date(timeIntervalSince1970: 0),
            scoringModelVersion: config.scoringModelVersion,
            thumbnailConfigVersion: config.thumbnailConfigVersion,
            entries: [
                BestShotCalibrationCluster(
                    clusterID: "mixed",
                    category: .people,
                    candidates: [
                        makeCandidate("measured", globalSharpness: 40, faces: [Self.face()], rejections: .empty),
                        makeCandidate(
                            "all-rejected",
                            globalSharpness: 38,
                            faces: [],
                            rejections: FaceRejectionCounts(tooSmallInFrame: 2, insufficientResolution: 1)
                        ),
                        makeCandidate("nobody", globalSharpness: 36, faces: [], rejections: .empty)
                    ],
                    humanBestShotID: "measured"
                )
            ]
        )

        let faces = MetricsReport.compute(corpus: corpus, config: config).overall.faces

        XCTAssertEqual(faces.candidateCount, 3)
        XCTAssertEqual(faces.withFacesCount, 1)
        XCTAssertEqual(faces.rejectedOnlyCount, 1)
        XCTAssertEqual(faces.unknownRejectionCount, 0)
        XCTAssertEqual(faces.rejections.tooSmallInFrame, 2)
        XCTAssertEqual(faces.rejections.insufficientResolution, 1)
        XCTAssertEqual(faces.rejections.total, 3)
    }

    /// A corpus exported before the counts existed cannot answer the question,
    /// and the report has to say so rather than reporting zero rejections.
    func testCandidatesWithoutRejectionCountsAreReportedAsUnknown() {
        let faces = MetricsReport.compute(corpus: makeCorpus(), config: config).overall.faces

        XCTAssertGreaterThan(faces.candidateCount, 0)
        XCTAssertEqual(faces.unknownRejectionCount, faces.candidateCount)
        XCTAssertEqual(faces.rejectedOnlyCount, 0)
        XCTAssertTrue(faces.rejections.isEmpty)
    }

    private static func face() -> FaceQualitySignal {
        FaceQualitySignal(
            detectionConfidence: 0.95,
            boxPixelSize: 20,
            sourcePixelSize: 96,
            sharpness: 30,
            hasClosedEyes: false,
            isCroppedByFrame: false
        )
    }

    // MARK: - Helpers

    private func makeCandidate(
        _ assetID: String,
        globalSharpness: Double,
        pixelWidth: Int = 4000,
        pixelHeight: Int = 3000,
        faces: [FaceQualitySignal]? = nil,
        rejections: FaceRejectionCounts? = nil
    ) -> BestShotCalibrationCandidate {
        BestShotCalibrationCandidate(
            assetID: assetID,
            signals: PhotoQualitySignals(
                globalSharpness: globalSharpness,
                subjectLumaStdDev: 0.25,
                noiseEstimate: 0.1,
                faceSignals: faces,
                rejectedFaceCounts: rejections,
                pixelArea: Int64(pixelWidth * pixelHeight)
            ),
            creationDate: Date(timeIntervalSince1970: 1_000),
            modificationDate: Date(timeIntervalSince1970: 1_000),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }
}
