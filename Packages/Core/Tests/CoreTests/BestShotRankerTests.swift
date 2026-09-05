import XCTest
@testable import Core

final class BestShotRankerTests: XCTestCase {
    private let config = PhotoQualityScoringConfig.current

    // MARK: - Requirements from the task

    func testSharpNonFavoriteBeatsBlurredFavorite() {
        let blurredFavorite = makeSnapshot("blurred", isFavorite: true)
        let sharp = makeSnapshot("sharp")

        let decision = BestShotRanker.decide(
            snapshots: [blurredFavorite, sharp],
            scores: makeScores([
                makeScore("blurred", globalSharpness: 12),
                makeScore("sharp", globalSharpness: 60)
            ])
        )

        XCTAssertEqual(decision.localIdentifier, "sharp")
        XCTAssertEqual(decision.confidence, .automatic)
        XCTAssertTrue(decision.reasonCodes.contains(.sharper))
    }

    func testFavoriteStillWinsBetweenComparablyGoodPhotos() {
        // Favorite stays a positive signal — it just cannot outrank a defect.
        let favorite = makeSnapshot("favorite", isFavorite: true)
        let other = makeSnapshot("other")

        let decision = BestShotRanker.decide(
            snapshots: [favorite, other],
            scores: makeScores([
                makeScore("favorite", globalSharpness: 50),
                makeScore("other", globalSharpness: 50)
            ])
        )

        XCTAssertEqual(decision.rankedCandidates.first?.localIdentifier, "favorite")
    }

    func testSmallerSharpFrameBeatsHighResolutionMotionBlur() {
        let bigBlurred = makeSnapshot("big", pixelWidth: 8000, pixelHeight: 6000)
        let smallSharp = makeSnapshot("small", pixelWidth: 2000, pixelHeight: 1500)

        let decision = BestShotRanker.decide(
            snapshots: [bigBlurred, smallSharp],
            scores: makeScores([
                makeScore("big", globalSharpness: 14),
                makeScore("small", globalSharpness: 55)
            ])
        )

        XCTAssertEqual(decision.localIdentifier, "small")
    }

    func testFaceInFocusBeatsSharpBackgroundWithBlurredFace() {
        let sharpBackground = makeSnapshot("background")
        let faceInFocus = makeSnapshot("face")

        let decision = BestShotRanker.decide(
            snapshots: [sharpBackground, faceInFocus],
            scores: makeScores([
                makeScore(
                    "background",
                    globalSharpness: 70,
                    subjectSharpness: 8,
                    faces: [makeFace(sharpness: 8)]
                ),
                makeScore(
                    "face",
                    globalSharpness: 40,
                    subjectSharpness: 60,
                    faces: [makeFace(sharpness: 60)]
                )
            ])
        )

        XCTAssertEqual(decision.localIdentifier, "face")
        XCTAssertTrue(decision.reasonCodes.contains(.faceInFocus) || decision.reasonCodes.contains(.sharper))
    }

    func testOpenEyesBeatClosedEyesInTheSameBurst() {
        let closed = makeSnapshot("closed")
        let open = makeSnapshot("open")

        let decision = BestShotRanker.decide(
            snapshots: [closed, open],
            scores: makeScores([
                makeScore(
                    "closed",
                    globalSharpness: 50,
                    subjectSharpness: 50,
                    faces: [makeFace(sharpness: 50, hasClosedEyes: true)]
                ),
                makeScore(
                    "open",
                    globalSharpness: 50,
                    subjectSharpness: 50,
                    faces: [makeFace(sharpness: 50, hasClosedEyes: false)]
                )
            ])
        )

        XCTAssertEqual(decision.localIdentifier, "open")
        XCTAssertTrue(decision.reasonCodes.contains(.openEyes))
    }

    func testCorrectlyExposedFrameBeatsBlownOutFrame() {
        let blownOut = makeSnapshot("blown")
        let exposed = makeSnapshot("exposed")

        let decision = BestShotRanker.decide(
            snapshots: [blownOut, exposed],
            scores: makeScores([
                makeScore("blown", globalSharpness: 50, brightClippedFraction: 0.30),
                makeScore("exposed", globalSharpness: 50, brightClippedFraction: 0.01)
            ])
        )

        XCTAssertEqual(decision.localIdentifier, "exposed")
        XCTAssertTrue(decision.reasonCodes.contains(.betterExposure))
    }

    func testFavoriteBonusDoesNotApplyToCriticallyBlurredCandidate() {
        let blurredFavorite = makeSnapshot("blurred", isFavorite: true)
        let sharpOne = makeSnapshot("sharp1")
        let sharpTwo = makeSnapshot("sharp2")

        let decision = BestShotRanker.decide(
            snapshots: [blurredFavorite, sharpOne, sharpTwo],
            scores: makeScores([
                makeScore("blurred", globalSharpness: 10),
                makeScore("sharp1", globalSharpness: 60),
                makeScore("sharp2", globalSharpness: 58)
            ])
        )

        let blurredCandidate = decision.rankedCandidates.first { $0.localIdentifier == "blurred" }
        XCTAssertEqual(blurredCandidate?.isExcluded, true)
        XCTAssertNotEqual(decision.localIdentifier, "blurred")
    }

    func testWeakClusterDoesNotClaimABestShot() {
        let snapshots = ["a", "b", "c"].map { makeSnapshot($0) }
        let decision = BestShotRanker.decide(
            snapshots: snapshots,
            scores: makeScores([
                makeScore("a", globalSharpness: 4),
                makeScore("b", globalSharpness: 3.5),
                makeScore("c", globalSharpness: 3.8)
            ])
        )

        XCTAssertEqual(decision.confidence, .unresolved)
        XCTAssertNil(decision.localIdentifier)
        // Weak photos are still listed; nothing is hidden from the user.
        XCTAssertEqual(decision.rankedCandidates.count, 3)
        XCTAssertFalse(decision.rankedCandidates.contains { $0.isExcluded })
    }

    func testNearlyEqualScoresStayUnresolvedButKeepAStableOrder() {
        let snapshots = [
            makeSnapshot("a", creationDate: Date(timeIntervalSince1970: 100)),
            makeSnapshot("b", creationDate: Date(timeIntervalSince1970: 100)),
            makeSnapshot("c", creationDate: Date(timeIntervalSince1970: 100))
        ]
        let scores = makeScores([
            makeScore("a", globalSharpness: 40),
            makeScore("b", globalSharpness: 40),
            makeScore("c", globalSharpness: 40)
        ])

        let first = BestShotRanker.decide(snapshots: snapshots, scores: scores)
        let second = BestShotRanker.decide(snapshots: snapshots.reversed(), scores: scores)

        XCTAssertEqual(first.confidence, .unresolved)
        XCTAssertEqual(
            first.rankedCandidates.map(\.localIdentifier),
            second.rankedCandidates.map(\.localIdentifier)
        )
        XCTAssertEqual(first.rankedCandidates.first?.localIdentifier, "a")
    }

    func testRepeatedAnalysisOfAnUnchangedClusterReturnsTheSameWinner() {
        let snapshots = [makeSnapshot("a"), makeSnapshot("b"), makeSnapshot("c")]
        let scores = makeScores([
            makeScore("a", globalSharpness: 20),
            makeScore("b", globalSharpness: 65),
            makeScore("c", globalSharpness: 30)
        ])

        let first = BestShotRanker.decide(snapshots: snapshots, scores: scores)
        let second = BestShotRanker.decide(snapshots: snapshots.shuffled(), scores: scores)

        XCTAssertEqual(first.localIdentifier, "b")
        XCTAssertEqual(first.localIdentifier, second.localIdentifier)
        XCTAssertEqual(first.confidence, second.confidence)
    }

    /// The face ROI is sampled on its own, larger grid, so its Laplacian is far
    /// smaller than the frame's. The absolute floor must be judged on the frame,
    /// or every portrait cluster is declared weak.
    func testPortraitClusterIsNotDeclaredWeakBecauseOfTheFaceCropScale() {
        let decision = BestShotRanker.decide(
            snapshots: [makeSnapshot("sharp-face"), makeSnapshot("soft-face")],
            scores: makeScores([
                makeScore(
                    "sharp-face",
                    globalSharpness: 40,
                    subjectSharpness: 6,
                    faces: [makeFace(sharpness: 6)]
                ),
                makeScore(
                    "soft-face",
                    globalSharpness: 30,
                    subjectSharpness: 2,
                    faces: [makeFace(sharpness: 2)]
                )
            ])
        )

        XCTAssertEqual(decision.localIdentifier, "sharp-face")
        XCTAssertNotEqual(decision.confidence, .unresolved)
    }

    func testClosedEyesAreExplainedAsOpenEyesRatherThanSharpness() {
        let decision = BestShotRanker.decide(
            snapshots: [makeSnapshot("open"), makeSnapshot("closed")],
            scores: makeScores([
                makeScore(
                    "open",
                    globalSharpness: 50,
                    subjectSharpness: 50,
                    faces: [makeFace(sharpness: 50, hasClosedEyes: false)]
                ),
                makeScore(
                    "closed",
                    globalSharpness: 50,
                    subjectSharpness: 50,
                    faces: [makeFace(sharpness: 50, hasClosedEyes: true)]
                )
            ])
        )

        XCTAssertEqual(decision.localIdentifier, "open")
        XCTAssertEqual(decision.reasonCodes.first, .openEyes)
        XCTAssertFalse(
            decision.reasonCodes.contains(.sharper),
            "Both frames are equally sharp — the eyes are the reason"
        )
    }

    // MARK: - Fallbacks

    func testMissingSignalsFallBackToMetadataRanking() {
        let favorite = makeSnapshot("favorite", isFavorite: true)
        let plain = makeSnapshot("plain")

        let decision = BestShotRanker.decide(snapshots: [favorite, plain], scores: [:])

        XCTAssertEqual(decision.localIdentifier, "favorite")
        XCTAssertEqual(decision.confidence, .automatic)
        XCTAssertTrue(decision.reasonCodes.isEmpty)
        XCTAssertEqual(decision.rankedCandidates.count, 2)
    }

    func testFailedAnalysisIsIgnoredWithoutLosingThePhoto() {
        let broken = makeSnapshot("broken")
        let sharpOne = makeSnapshot("sharp1")
        let sharpTwo = makeSnapshot("sharp2")

        let decision = BestShotRanker.decide(
            snapshots: [broken, sharpOne, sharpTwo],
            scores: makeScores([
                PhotoQualityScore(
                    localIdentifier: "broken",
                    sourceModificationDate: nil,
                    scoringModelVersion: config.scoringModelVersion,
                    thumbnailConfigVersion: config.thumbnailConfigVersion,
                    signals: .failed(.assetUnavailable)
                ),
                makeScore("sharp1", globalSharpness: 60),
                makeScore("sharp2", globalSharpness: 30)
            ])
        )

        XCTAssertEqual(decision.localIdentifier, "sharp1")
        XCTAssertFalse(decision.rankedCandidates.contains { $0.localIdentifier == "broken" })
        // A row that says "could not measure" is not coverage: the ranking has
        // no idea whether the broken photo was the better one.
        XCTAssertEqual(decision.confidence, .lowConfidence)
    }

    func testAFailedMeasurementDowngradesTheMetadataFallbackToo() {
        let decision = BestShotRanker.decide(
            snapshots: [makeSnapshot("broken"), makeSnapshot("only-good")],
            scores: makeScores([
                PhotoQualityScore(
                    localIdentifier: "broken",
                    sourceModificationDate: nil,
                    scoringModelVersion: config.scoringModelVersion,
                    thumbnailConfigVersion: config.thumbnailConfigVersion,
                    signals: .failed(.assetUnavailable)
                ),
                makeScore("only-good", globalSharpness: 60)
            ])
        )

        // One usable photo falls back to metadata ranking, but measuring was
        // attempted and failed, so the badge must not claim certainty.
        XCTAssertEqual(decision.confidence, .lowConfidence)
    }

    func testOneMeasuredPhotoAndOneUnmeasuredOneIsNotConfident() {
        let decision = BestShotRanker.decide(
            snapshots: [makeSnapshot("measured"), makeSnapshot("never-measured")],
            scores: makeScores([makeScore("measured", globalSharpness: 60)])
        )

        // Only one photo is usable, so this lands in the metadata fallback. The
        // missing row is not a failure and not coverage either: nothing is known
        // about the second photo, so the badge cannot claim the first one wins.
        XCTAssertEqual(decision.confidence, .lowConfidence)
    }

    func testUnmeasuredClusterKeepsTheConfidentMetadataBadge() {
        let decision = BestShotRanker.decide(
            snapshots: [makeSnapshot("a"), makeSnapshot("b")],
            scores: [:]
        )

        // Nobody has measured this cluster yet. Metadata ranking is what the app
        // always shipped, so it keeps behaving exactly as before.
        XCTAssertEqual(decision.confidence, .automatic)
    }

    func testPartialCoverageNeverClaimsFullConfidence() {
        let decision = BestShotRanker.decide(
            snapshots: [makeSnapshot("a"), makeSnapshot("b"), makeSnapshot("unscored")],
            scores: makeScores([
                makeScore("a", globalSharpness: 60),
                makeScore("b", globalSharpness: 20)
            ])
        )

        XCTAssertEqual(decision.localIdentifier, "a")
        XCTAssertEqual(decision.confidence, .lowConfidence)
    }

    /// One measured photo next to one the analyzer never returned is partial
    /// knowledge, not a metadata-only cluster: the ranking cannot know whether
    /// the unmeasured photo was the better one.
    func testOneUsableScoreBesideAMissingOneIsNotConfident() {
        let decision = BestShotRanker.decide(
            snapshots: [makeSnapshot("measured"), makeSnapshot("never-analyzed")],
            scores: makeScores([makeScore("measured", globalSharpness: 60)])
        )

        XCTAssertEqual(decision.confidence, .lowConfidence)
        XCTAssertNotNil(decision.localIdentifier)
    }

    func testSinglePhotoClusterKeepsItsOnlyPhoto() {
        let decision = BestShotRanker.decide(
            snapshots: [makeSnapshot("only")],
            scores: makeScores([makeScore("only", globalSharpness: 50)])
        )

        XCTAssertEqual(decision.localIdentifier, "only")
        // Nothing is unknown about a cluster of one measured photo, so partial
        // coverage does not apply and the badge stays confident.
        XCTAssertEqual(decision.confidence, .automatic)
    }

    func testEmptyClusterDecidesNothing() {
        XCTAssertEqual(BestShotRanker.decide(snapshots: [], scores: [:]), .empty)
    }

    // MARK: - sharpnessRatios

    /// `sharpnessRatios` is the extracted computation `decide` itself uses to
    /// exclude a critically blurred frame; this asserts the two never
    /// disagree about which candidate that is.
    func testSharpnessRatiosAgreeWithDecidesOwnExclusion() {
        let blurred = makeSnapshot("blurred")
        let referenceOne = makeSnapshot("reference1")
        let referenceTwo = makeSnapshot("reference2")
        let snapshots = [blurred, referenceOne, referenceTwo]
        let scores = makeScores([
            makeScore("blurred", globalSharpness: 5),
            makeScore("reference1", globalSharpness: 60),
            makeScore("reference2", globalSharpness: 58)
        ])

        let ratios = BestShotRanker.sharpnessRatios(snapshots: snapshots, scores: scores, config: config)
        let excludedByRatio = Set(
            snapshots
                .filter { (ratios[$0.localIdentifier] ?? 1) < config.criticalSharpnessRatio }
                .map(\.localIdentifier)
        )
        XCTAssertEqual(excludedByRatio, ["blurred"])

        let decision = BestShotRanker.decide(snapshots: snapshots, scores: scores, config: config)
        let excludedByDecide = Set(
            decision.rankedCandidates.filter(\.isExcluded).map(\.localIdentifier)
        )
        XCTAssertEqual(excludedByDecide, excludedByRatio)
    }

    // MARK: - overrideExample

    func testChosenSharperFrameProducesAPositiveSharpnessDelta() throws {
        let sharp = makeSnapshot("sharp")
        let blurry = makeSnapshot("blurry")
        let snapshots = [sharp, blurry]
        let scores = makeScores([
            makeScore("sharp", globalSharpness: 60),
            makeScore("blurry", globalSharpness: 30)
        ])
        let decision = BestShotRanker.decide(snapshots: snapshots, scores: scores)
        XCTAssertEqual(decision.localIdentifier, "sharp")

        let example = BestShotRanker.overrideExample(
            snapshots: snapshots,
            scores: scores,
            chosen: "sharp",
            recommended: "blurry"
        )

        let example2 = try XCTUnwrap(example)
        XCTAssertGreaterThan(example2.componentDelta.sharpness, 0)
        // The chosen frame is strictly better and carries no penalty gap in
        // the other direction, so noise/exposure/resolution should not go
        // negative for it here (both frames share identical inputs there).
        XCTAssertGreaterThanOrEqual(example2.componentDelta.exposure, 0)
        XCTAssertGreaterThanOrEqual(example2.componentDelta.noiseArtifacts, 0)
    }

    func testOverrideExampleIsNilWhenChosenEqualsRecommended() {
        let snapshots = [makeSnapshot("a"), makeSnapshot("b")]
        let scores = makeScores([
            makeScore("a", globalSharpness: 60),
            makeScore("b", globalSharpness: 30)
        ])

        let example = BestShotRanker.overrideExample(
            snapshots: snapshots,
            scores: scores,
            chosen: "a",
            recommended: "a"
        )

        XCTAssertNil(example)
    }

    func testOverrideExampleIsNilWhenAnIdentifierIsNotInTheCluster() {
        let snapshots = [makeSnapshot("a"), makeSnapshot("b")]
        let scores = makeScores([
            makeScore("a", globalSharpness: 60),
            makeScore("b", globalSharpness: 30)
        ])

        let example = BestShotRanker.overrideExample(
            snapshots: snapshots,
            scores: scores,
            chosen: "a",
            recommended: "not-in-cluster"
        )

        XCTAssertNil(example)
    }

    func testOverrideExampleIsNilWhenEitherSideWasExcludedForCriticalBlur() {
        let blurred = makeSnapshot("blurred")
        let referenceOne = makeSnapshot("reference1")
        let referenceTwo = makeSnapshot("reference2")
        let snapshots = [blurred, referenceOne, referenceTwo]
        let scores = makeScores([
            makeScore("blurred", globalSharpness: 5),
            makeScore("reference1", globalSharpness: 60),
            makeScore("reference2", globalSharpness: 58)
        ])

        let exampleChosenExcluded = BestShotRanker.overrideExample(
            snapshots: snapshots,
            scores: scores,
            chosen: "blurred",
            recommended: "reference1"
        )
        let exampleRecommendedExcluded = BestShotRanker.overrideExample(
            snapshots: snapshots,
            scores: scores,
            chosen: "reference1",
            recommended: "blurred"
        )

        XCTAssertNil(exampleChosenExcluded)
        XCTAssertNil(exampleRecommendedExcluded)
    }

    func testClusterHasFacesReflectsWhetherTheClusterHasUsableFaceSignals() throws {
        let withFaces = [makeSnapshot("a"), makeSnapshot("b")]
        let facedScores = makeScores([
            makeScore("a", globalSharpness: 50, subjectSharpness: 50, faces: [makeFace(sharpness: 50)]),
            makeScore("b", globalSharpness: 40, subjectSharpness: 40, faces: [makeFace(sharpness: 40)])
        ])
        let faced = try XCTUnwrap(BestShotRanker.overrideExample(
            snapshots: withFaces,
            scores: facedScores,
            chosen: "a",
            recommended: "b"
        ))
        XCTAssertTrue(faced.clusterHasFaces)

        let withoutFaces = [makeSnapshot("c"), makeSnapshot("d")]
        let facelessScores = makeScores([
            makeScore("c", globalSharpness: 50),
            makeScore("d", globalSharpness: 40)
        ])
        let faceless = try XCTUnwrap(BestShotRanker.overrideExample(
            snapshots: withoutFaces,
            scores: facelessScores,
            chosen: "c",
            recommended: "d"
        ))
        XCTAssertFalse(faceless.clusterHasFaces)
    }

    func testOffsetDeltaIsSignedTowardTheFavoriteFrame() throws {
        // Keep both frames far from the critical-blur exclusion band and from
        // score clamping, differing only in favorite status.
        let favorite = makeSnapshot("favorite", isFavorite: true)
        let other = makeSnapshot("other")
        let snapshots = [favorite, other]
        let scores = makeScores([
            makeScore("favorite", globalSharpness: 50),
            makeScore("other", globalSharpness: 50)
        ])

        let favoriteChosen = try XCTUnwrap(BestShotRanker.overrideExample(
            snapshots: snapshots,
            scores: scores,
            chosen: "favorite",
            recommended: "other"
        ))
        let favoriteRecommended = try XCTUnwrap(BestShotRanker.overrideExample(
            snapshots: snapshots,
            scores: scores,
            chosen: "other",
            recommended: "favorite"
        ))

        XCTAssertGreaterThan(favoriteChosen.offsetDelta, 0)
        XCTAssertLessThan(favoriteRecommended.offsetDelta, 0)
    }

    func testScoringModelVersionIsCarriedFromThePassedConfig() {
        var customConfig = PhotoQualityScoringConfig.current
        customConfig.scoringModelVersion = 999
        let snapshots = [makeSnapshot("a"), makeSnapshot("b")]
        let scores = makeScores([
            makeScore("a", globalSharpness: 60),
            makeScore("b", globalSharpness: 30)
        ])

        let example = BestShotRanker.overrideExample(
            snapshots: snapshots,
            scores: scores,
            chosen: "a",
            recommended: "b",
            config: customConfig
        )

        XCTAssertEqual(example?.scoringModelVersion, 999)
    }

    func testBestShotOverrideExampleRoundTripsThroughCodable() throws {
        let example = BestShotOverrideExample(
            recordedAt: Date(timeIntervalSince1970: 12_345),
            clusterHasFaces: true,
            componentDelta: PhotoQualityScoringConfig.Weights(
                sharpness: 0.1,
                faceQuality: -0.2,
                exposure: 0.3,
                noiseArtifacts: -0.4,
                resolution: 0.5
            ),
            offsetDelta: -0.05,
            scoringModelVersion: 3
        )

        let data = try JSONEncoder().encode(example)
        let decoded = try JSONDecoder().decode(BestShotOverrideExample.self, from: data)

        XCTAssertEqual(decoded, example)
    }

    // MARK: - Helpers

    private func makeSnapshot(
        _ localIdentifier: String,
        isFavorite: Bool = false,
        pixelWidth: Int = 4000,
        pixelHeight: Int = 3000,
        creationDate: Date = Date(timeIntervalSince1970: 1_000)
    ) -> PhotoClusterAssetSnapshot {
        PhotoClusterAssetSnapshot(
            localIdentifier: localIdentifier,
            creationDate: creationDate,
            modificationDate: creationDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            isFavorite: isFavorite
        )
    }

    private func makeScore(
        _ localIdentifier: String,
        globalSharpness: Double,
        subjectSharpness: Double? = nil,
        darkClippedFraction: Double = 0,
        brightClippedFraction: Double = 0,
        subjectLumaStdDev: Double = 0.25,
        noiseEstimate: Double = 0.1,
        faces: [FaceQualitySignal]? = nil
    ) -> PhotoQualityScore {
        PhotoQualityScore(
            localIdentifier: localIdentifier,
            sourceModificationDate: Date(timeIntervalSince1970: 1_000),
            scoringModelVersion: config.scoringModelVersion,
            thumbnailConfigVersion: config.thumbnailConfigVersion,
            signals: PhotoQualitySignals(
                globalSharpness: globalSharpness,
                subjectSharpness: subjectSharpness,
                darkClippedFraction: darkClippedFraction,
                brightClippedFraction: brightClippedFraction,
                subjectLumaStdDev: subjectLumaStdDev,
                noiseEstimate: noiseEstimate,
                faceSignals: faces,
                pixelArea: 12_000_000
            )
        )
    }

    private func makeFace(
        sharpness: Double,
        hasClosedEyes: Bool? = false,
        isCroppedByFrame: Bool = false
    ) -> FaceQualitySignal {
        FaceQualitySignal(
            detectionConfidence: 0.9,
            boxPixelSize: 120,
            sharpness: sharpness,
            hasClosedEyes: hasClosedEyes,
            isCroppedByFrame: isCroppedByFrame
        )
    }

    private func makeScores(_ scores: [PhotoQualityScore]) -> [String: PhotoQualityScore] {
        Dictionary(uniqueKeysWithValues: scores.map { ($0.localIdentifier, $0) })
    }
}
