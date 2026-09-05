import XCTest
@testable import BestShotCalibration
@testable import Core

final class PersonalizationReportTests: XCTestCase {
    private let config = PhotoQualityScoringConfig.current

    // MARK: - Prefix parsing

    func testPrefixParsingAcceptsCommaSeparatedIntegers() throws {
        let sizes = try PersonalizationReport.parsePrefixes("10,30", corpusSize: 1000)
        XCTAssertEqual(sizes, [10, 30])
    }

    func testPrefixParsingResolvesAllToCorpusSizeAndCollapsesDuplicates() throws {
        let sizes = try PersonalizationReport.parsePrefixes("10,30,100,all", corpusSize: 30)
        // "all" clamps to 30, which collapses with the explicit "30".
        XCTAssertEqual(sizes, [10, 30])
    }

    func testPrefixParsingClampsOversizedValuesToCorpusSize() throws {
        let sizes = try PersonalizationReport.parsePrefixes("5,1000", corpusSize: 12)
        XCTAssertEqual(sizes, [5, 12])
    }

    func testPrefixParsingRejectsNonNumericToken() {
        XCTAssertThrowsError(try PersonalizationReport.parsePrefixes("10,abc", corpusSize: 100)) { error in
            XCTAssertEqual(error as? PersonalizationReport.PrefixParseError, .invalidToken("abc"))
        }
    }

    func testPrefixParsingRejectsNegativeNumber() {
        XCTAssertThrowsError(try PersonalizationReport.parsePrefixes("10,-5", corpusSize: 100)) { error in
            XCTAssertEqual(error as? PersonalizationReport.PrefixParseError, .invalidToken("-5"))
        }
    }

    // MARK: - Fit/eval split

    func testFitAndEvalSetsAreDisjointAndDeterministic() {
        // Deliberately out of clusterID order, so the test would fail if
        // PersonalizationReport trusted array order instead of sorting.
        let corpus = makeCorpus(clusterIDs: ["c", "a", "e", "b", "d"])

        let result = PersonalizationReport.run(corpus: corpus, prefixSizes: [2], global: config)
        let prefixResult = result.prefixResults[0]

        XCTAssertEqual(prefixResult.fitClusterIDs, ["a", "b"])
        XCTAssertEqual(prefixResult.evalClusterIDs, ["c", "d", "e"])
        XCTAssertTrue(Set(prefixResult.fitClusterIDs).isDisjoint(with: Set(prefixResult.evalClusterIDs)))

        // Running it again from the same corpus produces the identical split.
        let second = PersonalizationReport.run(corpus: corpus, prefixSizes: [2], global: config)
        XCTAssertEqual(prefixResult.fitClusterIDs, second.prefixResults[0].fitClusterIDs)
        XCTAssertEqual(prefixResult.evalClusterIDs, second.prefixResults[0].evalClusterIDs)
    }

    func testAllPrefixYieldsEmptyEvalSetWithoutCrashing() {
        let corpus = makeCorpus(clusterIDs: ["a", "b", "c"])
        let sizes = try! PersonalizationReport.parsePrefixes("all", corpusSize: corpus.entries.count)
        XCTAssertEqual(sizes, [3])

        let result = PersonalizationReport.run(corpus: corpus, prefixSizes: sizes, global: config)
        let prefixResult = result.prefixResults[0]

        XCTAssertEqual(prefixResult.fitClusterIDs.count, 3)
        XCTAssertTrue(prefixResult.evalClusterIDs.isEmpty)
        XCTAssertNil(prefixResult.baseline)
        XCTAssertNil(prefixResult.personalized)

        // Rendering must not crash or divide by zero on the empty eval set.
        let kfold = PersonalizationReport.runKFold(corpus: corpus, folds: 3, global: config)
        let report = ReportWriter.render(personalization: result, kfold: kfold, corpusClusterCount: corpus.entries.count)
        XCTAssertTrue(report.contains("no eval clusters"))
    }

    func testPrefixSizeIsClampedToCorpusSizeWhenRunDirectly() {
        let corpus = makeCorpus(clusterIDs: ["a", "b", "c"])
        let result = PersonalizationReport.run(corpus: corpus, prefixSizes: [999], global: config)
        XCTAssertEqual(result.prefixResults[0].prefixSize, 3)
        XCTAssertTrue(result.prefixResults[0].evalClusterIDs.isEmpty)
    }

    // MARK: - Synthesised examples match overrideExample directly

    func testSynthesizedExampleMatchesDirectOverrideExampleCall() {
        // A disagreement cluster: the ranker should pick "sharp" but the human
        // picked "soft".
        let cluster = BestShotCalibrationCluster(
            clusterID: "disagreement",
            category: .landscape,
            candidates: [
                makeCandidate("sharp", globalSharpness: 55),
                makeCandidate("soft", globalSharpness: 50),
            ],
            humanBestShotID: "soft"
        )

        let scores = cluster.scores(
            scoringModelVersion: config.scoringModelVersion,
            thumbnailConfigVersion: config.thumbnailConfigVersion
        )
        let decision = BestShotRanker.decide(snapshots: cluster.snapshots, scores: scores, config: config)
        XCTAssertEqual(decision.localIdentifier, "sharp", "ranker should disagree with the human pick here")

        let expected = BestShotRanker.overrideExample(
            snapshots: cluster.snapshots,
            scores: scores,
            chosen: "soft",
            recommended: "sharp",
            now: PersonalizationReport.fixedRecordedAt,
            config: config
        )
        XCTAssertNotNil(expected)

        let build = PersonalizationReport.fitExamples(from: [cluster], config: config)
        XCTAssertEqual(build.examples, [expected].compactMap { $0 })
        XCTAssertEqual(build.outcome.exampleCount, 1)
        XCTAssertEqual(build.outcome.agreementClusterCount, 0)
        XCTAssertEqual(build.outcome.unresolvedClusterCount, 0)
        XCTAssertEqual(build.outcome.refusedExampleCount, 0)
    }

    func testAgreementClusterProducesNoExample() {
        let cluster = BestShotCalibrationCluster(
            clusterID: "agree",
            category: .landscape,
            candidates: [
                makeCandidate("sharp", globalSharpness: 60),
                makeCandidate("blurred", globalSharpness: 10),
            ],
            humanBestShotID: "sharp"
        )

        let build = PersonalizationReport.fitExamples(from: [cluster], config: config)
        XCTAssertTrue(build.examples.isEmpty)
        XCTAssertEqual(build.outcome.agreementClusterCount, 1)
        XCTAssertEqual(build.outcome.exampleCount, 0)
    }

    func testUnresolvedClusterProducesNoExampleAndIsCountedSeparately() {
        // Both candidates fall below the absolute sharpness floor, so the
        // ranker comes out `.unresolved` with no winner to disagree with.
        let cluster = BestShotCalibrationCluster(
            clusterID: "weak",
            category: .night,
            candidates: [
                makeCandidate("weak-a", globalSharpness: 4),
                makeCandidate("weak-b", globalSharpness: 3),
            ],
            humanBestShotID: "weak-a"
        )

        let build = PersonalizationReport.fitExamples(from: [cluster], config: config)
        XCTAssertTrue(build.examples.isEmpty)
        XCTAssertEqual(build.outcome.unresolvedClusterCount, 1)
        XCTAssertEqual(build.outcome.agreementClusterCount, 0)
        XCTAssertEqual(build.outcome.refusedExampleCount, 0)
    }

    // MARK: - Below-minimum prefixes report as not engaged

    func testSmallPrefixLeavesPersonalizationUnengaged() {
        // A handful of disagreement clusters — far below
        // PersonalWeightModel's minimum example count — must not move the
        // weights away from the global config.
        var entries: [BestShotCalibrationCluster] = []
        for index in 0..<3 {
            entries.append(
                BestShotCalibrationCluster(
                    clusterID: "disagree-\(index)",
                    category: .landscape,
                    candidates: [
                        makeCandidate("sharp-\(index)", globalSharpness: 55),
                        makeCandidate("soft-\(index)", globalSharpness: 50),
                    ],
                    humanBestShotID: "soft-\(index)"
                )
            )
        }
        entries.append(
            BestShotCalibrationCluster(
                clusterID: "extra",
                category: .landscape,
                candidates: [makeCandidate("extra-only", globalSharpness: 45)],
                humanBestShotID: "extra-only"
            )
        )
        let corpus = BestShotCalibrationCorpus(
            exportedAt: Date(timeIntervalSince1970: 0),
            scoringModelVersion: config.scoringModelVersion,
            thumbnailConfigVersion: config.thumbnailConfigVersion,
            entries: entries
        )

        let result = PersonalizationReport.run(corpus: corpus, prefixSizes: [3], global: config)
        let prefixResult = result.prefixResults[0]

        XCTAssertFalse(prefixResult.personalizationEngaged)
        XCTAssertEqual(prefixResult.personalizedConfig.weightsWithoutFaces, config.weightsWithoutFaces)
        XCTAssertEqual(prefixResult.personalizedConfig.weightsWithFaces, config.weightsWithFaces)
    }

    // MARK: - Folds parsing

    func testFoldsParsingAcceptsValueInRange() throws {
        XCTAssertEqual(try PersonalizationReport.parseFolds("5", corpusSize: 75), 5)
        XCTAssertEqual(try PersonalizationReport.parseFolds("2", corpusSize: 2), 2)
    }

    func testFoldsParsingRejectsNonNumericToken() {
        XCTAssertThrowsError(try PersonalizationReport.parseFolds("abc", corpusSize: 75)) { error in
            XCTAssertEqual(error as? PersonalizationReport.FoldsParseError, .invalidValue("abc"))
        }
    }

    func testFoldsParsingRejectsZeroOneAndNegative() {
        for token in ["0", "1", "-3"] {
            XCTAssertThrowsError(try PersonalizationReport.parseFolds(token, corpusSize: 75), "token \(token)") { error in
                guard case .outOfRange = error as? PersonalizationReport.FoldsParseError else {
                    return XCTFail("expected .outOfRange for '\(token)', got \(error)")
                }
            }
        }
    }

    func testFoldsParsingRejectsValueAboveCorpusSize() {
        XCTAssertThrowsError(try PersonalizationReport.parseFolds("10", corpusSize: 5)) { error in
            XCTAssertEqual(
                error as? PersonalizationReport.FoldsParseError,
                .outOfRange(10, corpusSize: 5)
            )
        }
    }

    // MARK: - K-fold assignment

    func testFoldAssignmentIsIndexModuloKOnClusterIDSortOrder() {
        // Deliberately out of clusterID order, same as the prefix disjointness
        // test — the fold split must sort first, not trust array order.
        let corpus = makeCorpus(clusterIDs: ["e", "c", "a", "d", "b"])
        // Sorted: a(0) b(1) c(2) d(3) e(4); k=2 -> fold0={a,c,e} fold1={b,d}
        let result = PersonalizationReport.runKFold(corpus: corpus, folds: 2, global: config)

        XCTAssertEqual(result.folds, 2)
        XCTAssertEqual(result.foldResults.count, 2)
        XCTAssertEqual(result.foldResults[0].evalClusterIDs, ["a", "c", "e"])
        XCTAssertEqual(result.foldResults[1].evalClusterIDs, ["b", "d"])
    }

    func testFoldFitAndEvalSetsAreDisjointForEveryFold() {
        let corpus = makeCorpus(clusterIDs: (0..<20).map { "c\($0)" })
        let result = PersonalizationReport.runKFold(corpus: corpus, folds: 5, global: config)

        XCTAssertEqual(result.foldResults.count, 5)
        for fold in result.foldResults {
            XCTAssertTrue(Set(fold.fitClusterIDs).isDisjoint(with: Set(fold.evalClusterIDs)))
            XCTAssertEqual(fold.fitClusterIDs.count + fold.evalClusterIDs.count, 20)
            XCTAssertFalse(fold.evalClusterIDs.isEmpty)
        }

        // Every cluster is evaluated in exactly one fold.
        let allEvalIDs = result.foldResults.flatMap(\.evalClusterIDs)
        XCTAssertEqual(Set(allEvalIDs).count, 20)
        XCTAssertEqual(allEvalIDs.count, 20)
    }

    func testKFoldAggregateSumsAcrossFolds() {
        let corpus = makeCorpus(clusterIDs: (0..<20).map { "c\($0)" })
        let result = PersonalizationReport.runKFold(corpus: corpus, folds: 5, global: config)

        let expectedClusterCount = result.foldResults.compactMap(\.baseline).reduce(0) { $0 + $1.clusterCount }
        XCTAssertEqual(result.aggregateBaseline.clusterCount, expectedClusterCount)
        XCTAssertEqual(result.aggregateBaseline.clusterCount, 20, "every cluster is held out exactly once")

        let expectedCorrect = result.foldResults.compactMap(\.personalized).reduce(0) { $0 + $1.correctClusterCount }
        XCTAssertEqual(result.aggregatePersonalized.correctClusterCount, expectedCorrect)
    }

    func testWithFacesBranchNeverEngagesWithoutFaceBearingClusters() {
        // No candidate in this corpus carries a face signal, so the
        // with-faces branch must never engage no matter how many folds run,
        // and the corpus-level face count must read zero.
        let corpus = makeCorpus(clusterIDs: (0..<20).map { "c\($0)" })
        let result = PersonalizationReport.runKFold(corpus: corpus, folds: 5, global: config)

        XCTAssertFalse(result.withFacesEngagedAnyFold)
        XCTAssertEqual(result.faceBearingClusterCount, 0)
        for fold in result.foldResults {
            XCTAssertFalse(fold.withFacesEngaged)
        }
    }

    // MARK: - Helpers

    private func makeCorpus(clusterIDs: [String]) -> BestShotCalibrationCorpus {
        let entries = clusterIDs.map { id -> BestShotCalibrationCluster in
            BestShotCalibrationCluster(
                clusterID: id,
                category: .landscape,
                candidates: [
                    makeCandidate("\(id)-sharp", globalSharpness: 60),
                    makeCandidate("\(id)-blurred", globalSharpness: 10),
                ],
                humanBestShotID: "\(id)-sharp"
            )
        }
        return BestShotCalibrationCorpus(
            exportedAt: Date(timeIntervalSince1970: 0),
            scoringModelVersion: config.scoringModelVersion,
            thumbnailConfigVersion: config.thumbnailConfigVersion,
            entries: entries
        )
    }

    private func makeCandidate(
        _ assetID: String,
        globalSharpness: Double,
        pixelWidth: Int = 4000,
        pixelHeight: Int = 3000
    ) -> BestShotCalibrationCandidate {
        BestShotCalibrationCandidate(
            assetID: assetID,
            signals: PhotoQualitySignals(
                globalSharpness: globalSharpness,
                subjectLumaStdDev: 0.25,
                noiseEstimate: 0.1,
                faceSignals: nil,
                rejectedFaceCounts: nil,
                pixelArea: Int64(pixelWidth * pixelHeight)
            ),
            creationDate: Date(timeIntervalSince1970: 1_000),
            modificationDate: Date(timeIntervalSince1970: 1_000),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }
}
