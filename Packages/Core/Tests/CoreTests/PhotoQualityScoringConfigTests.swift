import XCTest
@testable import Core

final class PhotoQualityScoringConfigTests: XCTestCase {
    func testShippedConfigRoundTripsThroughCoding() throws {
        let data = try JSONEncoder().encode(PhotoQualityScoringConfig.current)
        let decoded = try JSONDecoder().decode(PhotoQualityScoringConfig.self, from: data)

        XCTAssertEqual(decoded, PhotoQualityScoringConfig.current)
    }

    func testWeightSetsSumToOne() {
        XCTAssertEqual(PhotoQualityScoringConfig.current.weightsWithoutFaces.total, 1, accuracy: 0.000_1)
        XCTAssertEqual(PhotoQualityScoringConfig.current.weightsWithFaces.total, 1, accuracy: 0.000_1)
    }

    func testFaceWeightIsUnusedWithoutFaces() {
        XCTAssertEqual(PhotoQualityScoringConfig.current.weightsWithoutFaces.faceQuality, 0)
    }

    /// Guards the cache contract: a formula change without a version bump would
    /// keep serving scores computed by the previous model.
    func testShippedVersionsMatchTheDocumentedModel() {
        XCTAssertEqual(PhotoQualityScoringConfig.current.scoringModelVersion, 1)
        XCTAssertEqual(PhotoQualityScoringConfig.current.thumbnailConfigVersion, 3)
    }

    // MARK: - Wire format

    /// A candidate config written by `bestshot-calibrate sweep` before the face
    /// gate changed. It carries the retired `minimumFacePixelSize` and lacks
    /// `minimumFaceFrameFraction`, `maxFaceSourceLongSide` and
    /// `faceMatchMinimumIoU`. Synthesized decoding failed it with `keyNotFound`,
    /// which broke `report --config` on files already on disk.
    func testACandidateConfigWrittenBeforeTheFaceGateChangedStillDecodes() throws {
        let legacy = """
        {
          "scoringModelVersion": 1,
          "thumbnailConfigVersion": 1,
          "analysisImageLongSide": 256,
          "faceCropSide": 256,
          "minimumAnalysisLongSide": 128,
          "sharpnessGridSide": 128,
          "maxConcurrentAnalysisTasks": 4,
          "absoluteSharpnessFloor": 14,
          "criticalSharpnessRatio": 0.6,
          "minimumFacePixelSize": 64,
          "minimumFaceDetectionConfidence": 0.7
        }
        """

        let decoded = try JSONDecoder().decode(
            PhotoQualityScoringConfig.self,
            from: Data(legacy.utf8)
        )
        let defaults = PhotoQualityScoringConfig()

        // What the file actually said is kept — this is a swept candidate.
        XCTAssertEqual(decoded.absoluteSharpnessFloor, 14)
        XCTAssertEqual(decoded.criticalSharpnessRatio, 0.6)
        XCTAssertEqual(decoded.analysisImageLongSide, 256)

        // What it could not say takes today's value.
        XCTAssertEqual(decoded.minimumFaceFrameFraction, defaults.minimumFaceFrameFraction)
        XCTAssertEqual(decoded.maxFaceSourceLongSide, defaults.maxFaceSourceLongSide)
        XCTAssertEqual(decoded.faceMatchMinimumIoU, defaults.faceMatchMinimumIoU)
        XCTAssertEqual(decoded.weightsWithFaces, defaults.weightsWithFaces)

        // The retired pixel gate is discarded, not translated: 64 / 256 = 0.25
        // is the gate this release removed for rejecting almost every real face.
        XCTAssertNotEqual(decoded.minimumFaceFrameFraction, 64.0 / 256.0)
    }

    // MARK: - Face gate

    /// The gate that made face scoring dead code: 64 pixels of a 256-pixel
    /// analysis image is a quarter of the long side, so only a selfie passed.
    /// A fraction cannot silently mean something else when the thumbnail size
    /// changes.
    func testTheFaceGateIsAFractionSmallEnoughForAnOrdinaryPortrait() {
        let config = PhotoQualityScoringConfig.current
        // The gate as it shipped: 64 absolute pixels of the 256-pixel frame.
        let oldAbsoluteGateAsFraction = 64.0 / 256.0

        XCTAssertLessThan(config.minimumFaceFrameFraction, oldAbsoluteGateAsFraction / 4)
        XCTAssertGreaterThan(config.minimumFaceFrameFraction, 0)
    }

    /// The two gates have to agree: a face the frame-fraction gate accepts must
    /// be able to reach `faceCropSide` real pixels within the source ceiling,
    /// or it would pass the first gate only to be thrown away by the second.
    func testEveryAcceptedFaceCanReachTheCropSideWithinTheSourceCeiling() {
        let config = PhotoQualityScoringConfig.current
        let smallestAcceptable = config.minimumFaceFrameFraction
        let side = config.faceSourceLongSide(smallestAcceptedFaceFraction: smallestAcceptable)

        XCTAssertLessThanOrEqual(side, config.maxFaceSourceLongSide)
        XCTAssertGreaterThanOrEqual(
            Double(side) * smallestAcceptable,
            Double(config.faceCropSide)
        )
    }

    func testFaceSourceStaysWithTheAnalysisImageWhenItAlreadySuffices() {
        let config = PhotoQualityScoringConfig.current
        // A face filling half the frame already clears the crop side outright.
        XCTAssertEqual(
            config.faceSourceLongSide(smallestAcceptedFaceFraction: 0.5),
            config.analysisImageLongSide
        )
    }

    func testFaceSourceIsCappedRatherThanGrowingWithoutBound() {
        let config = PhotoQualityScoringConfig.current
        XCTAssertEqual(
            config.faceSourceLongSide(smallestAcceptedFaceFraction: 0.0001),
            config.maxFaceSourceLongSide
        )
        XCTAssertEqual(
            config.faceSourceLongSide(smallestAcceptedFaceFraction: 0),
            config.maxFaceSourceLongSide
        )
    }

    func testFaceSourceIsSizedSoTheSmallestFaceFillsTheCropGrid() {
        let config = PhotoQualityScoringConfig.current
        let side = config.faceSourceLongSide(smallestAcceptedFaceFraction: 0.1)

        XCTAssertEqual(side, config.faceCropSide * 10)
    }

    func testFavoriteCannotOutweighAQualityDefect() {
        let config = PhotoQualityScoringConfig.current
        XCTAssertLessThan(config.favoriteBonus, config.weakSharpnessPenalty)
        XCTAssertLessThanOrEqual(config.weightsWithFaces.resolution, config.resolutionWeightCap)
    }

    func testConfidenceBandsAreOrdered() {
        let config = PhotoQualityScoringConfig.current
        XCTAssertLessThan(config.lowConfidenceMinimumMargin, config.automaticSelectionMinimumMargin)
        XCTAssertLessThan(config.criticalSharpnessRatio, config.strongPenaltySharpnessRatio)
        XCTAssertLessThan(config.strongPenaltySharpnessRatio, config.weakPenaltySharpnessRatio)
        XCTAssertLessThan(config.clippingFreeFraction, config.clippingFullPenaltyFraction)
        XCTAssertLessThan(config.clippingFullPenaltyFraction, config.clippingCriticalFraction)
    }

    func testScoreFreshnessFollowsTheCacheKey() {
        let date = Date(timeIntervalSince1970: 500)
        let score = PhotoQualityScore(
            localIdentifier: "a",
            sourceModificationDate: date,
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1,
            signals: PhotoQualitySignals(globalSharpness: 20)
        )

        XCTAssertTrue(score.isFresh(modificationDate: date, scoringModelVersion: 1, thumbnailConfigVersion: 1))
        XCTAssertFalse(score.isFresh(
            modificationDate: date.addingTimeInterval(1),
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1
        ))
        XCTAssertFalse(score.isFresh(modificationDate: date, scoringModelVersion: 2, thumbnailConfigVersion: 1))
        XCTAssertFalse(score.isFresh(modificationDate: date, scoringModelVersion: 1, thumbnailConfigVersion: 2))
    }

    /// Phase 2 writes this flag; scoring must then keep the pre-enhancement
    /// signals instead of measuring Alike's own edit.
    func testEnhancedAssetsAreNotInvalidatedByTheirNewModificationDate() {
        let score = PhotoQualityScore(
            localIdentifier: "a",
            sourceModificationDate: Date(timeIntervalSince1970: 500),
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1,
            signals: PhotoQualitySignals(globalSharpness: 20),
            isAlikeEnhanced: true
        )

        XCTAssertTrue(score.isFresh(
            modificationDate: Date(timeIntervalSince1970: 9_000),
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1
        ))
    }

    /// After the edit these signals are the only surviving measurement of the
    /// original, and no version bump can bring the original pixels back — a
    /// re-score would measure Alike's own enhancement instead.
    func testEnhancedAssetsSurviveAScoringModelVersionBump() {
        let score = PhotoQualityScore(
            localIdentifier: "a",
            sourceModificationDate: Date(timeIntervalSince1970: 500),
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1,
            signals: PhotoQualitySignals(globalSharpness: 20),
            isAlikeEnhanced: true
        )

        XCTAssertTrue(score.isFresh(
            modificationDate: Date(timeIntervalSince1970: 9_000),
            scoringModelVersion: 2,
            thumbnailConfigVersion: 3
        ))
    }
}
