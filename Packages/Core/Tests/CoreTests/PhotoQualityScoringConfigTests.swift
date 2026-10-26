import Foundation
import Testing
@testable import Core

@Suite struct PhotoQualityScoringConfigTests {
    @Test func testShippedConfigRoundTripsThroughCoding() throws {
        let data = try JSONEncoder().encode(PhotoQualityScoringConfig.current)
        let decoded = try JSONDecoder().decode(PhotoQualityScoringConfig.self, from: data)

        #expect(decoded == PhotoQualityScoringConfig.current)
    }

    @Test func testWeightSetsSumToOne() {
        #expect(abs(PhotoQualityScoringConfig.current.weightsWithoutFaces.total - 1) <= 0.000_1)
        #expect(abs(PhotoQualityScoringConfig.current.weightsWithFaces.total - 1) <= 0.000_1)
    }

    @Test func testFaceWeightIsUnusedWithoutFaces() {
        #expect(PhotoQualityScoringConfig.current.weightsWithoutFaces.faceQuality == 0)
    }

    /// Guards the cache contract: a formula change without a version bump would
    /// keep serving scores computed by the previous model.
    @Test func testShippedVersionsMatchTheDocumentedModel() {
        #expect(PhotoQualityScoringConfig.current.scoringModelVersion == 1)
        #expect(PhotoQualityScoringConfig.current.thumbnailConfigVersion == 3)
    }

    // MARK: - Wire format

    /// A candidate config written by `bestshot-calibrate sweep` before the face
    /// gate changed. It carries the retired `minimumFacePixelSize` and lacks
    /// `minimumFaceFrameFraction`, `maxFaceSourceLongSide` and
    /// `faceMatchMinimumIoU`. Synthesized decoding failed it with `keyNotFound`,
    /// which broke `report --config` on files already on disk.
    @Test func testACandidateConfigWrittenBeforeTheFaceGateChangedStillDecodes() throws {
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
        #expect(decoded.absoluteSharpnessFloor == 14)
        #expect(decoded.criticalSharpnessRatio == 0.6)
        #expect(decoded.analysisImageLongSide == 256)

        // What it could not say takes today's value.
        #expect(decoded.minimumFaceFrameFraction == defaults.minimumFaceFrameFraction)
        #expect(decoded.maxFaceSourceLongSide == defaults.maxFaceSourceLongSide)
        #expect(decoded.faceMatchMinimumIoU == defaults.faceMatchMinimumIoU)
        #expect(decoded.weightsWithFaces == defaults.weightsWithFaces)

        // The retired pixel gate is discarded, not translated: 64 / 256 = 0.25
        // is the gate this release removed for rejecting almost every real face.
        #expect(decoded.minimumFaceFrameFraction != 64.0 / 256.0)
    }

    // MARK: - Face gate

    /// The gate that made face scoring dead code: 64 pixels of a 256-pixel
    /// analysis image is a quarter of the long side, so only a selfie passed.
    /// A fraction cannot silently mean something else when the thumbnail size
    /// changes.
    @Test func testTheFaceGateIsAFractionSmallEnoughForAnOrdinaryPortrait() {
        let config = PhotoQualityScoringConfig.current
        // The gate as it shipped: 64 absolute pixels of the 256-pixel frame.
        let oldAbsoluteGateAsFraction = 64.0 / 256.0

        #expect(config.minimumFaceFrameFraction < oldAbsoluteGateAsFraction / 4)
        #expect(config.minimumFaceFrameFraction > 0)
    }

    /// The two gates have to agree: a face the frame-fraction gate accepts must
    /// be able to reach `faceCropSide` real pixels within the source ceiling,
    /// or it would pass the first gate only to be thrown away by the second.
    @Test func testEveryAcceptedFaceCanReachTheCropSideWithinTheSourceCeiling() {
        let config = PhotoQualityScoringConfig.current
        let smallestAcceptable = config.minimumFaceFrameFraction
        let side = config.faceSourceLongSide(smallestAcceptedFaceFraction: smallestAcceptable)

        #expect(side <= config.maxFaceSourceLongSide)
        #expect(
            Double(side) * smallestAcceptable >= Double(config.faceCropSide)
        )
    }

    @Test func testFaceSourceStaysWithTheAnalysisImageWhenItAlreadySuffices() {
        let config = PhotoQualityScoringConfig.current
        // A face filling half the frame already clears the crop side outright.
        #expect(
            config.faceSourceLongSide(smallestAcceptedFaceFraction: 0.5) == config.analysisImageLongSide
        )
    }

    @Test func testFaceSourceIsCappedRatherThanGrowingWithoutBound() {
        let config = PhotoQualityScoringConfig.current
        #expect(
            config.faceSourceLongSide(smallestAcceptedFaceFraction: 0.0001) == config.maxFaceSourceLongSide
        )
        #expect(
            config.faceSourceLongSide(smallestAcceptedFaceFraction: 0) == config.maxFaceSourceLongSide
        )
    }

    @Test func testFaceSourceIsSizedSoTheSmallestFaceFillsTheCropGrid() {
        let config = PhotoQualityScoringConfig.current
        let side = config.faceSourceLongSide(smallestAcceptedFaceFraction: 0.1)

        #expect(side == config.faceCropSide * 10)
    }

    @Test func testFavoriteCannotOutweighAQualityDefect() {
        let config = PhotoQualityScoringConfig.current
        #expect(config.favoriteBonus < config.weakSharpnessPenalty)
        #expect(config.weightsWithFaces.resolution <= config.resolutionWeightCap)
    }

    @Test func testConfidenceBandsAreOrdered() {
        let config = PhotoQualityScoringConfig.current
        #expect(config.lowConfidenceMinimumMargin < config.automaticSelectionMinimumMargin)
        #expect(config.criticalSharpnessRatio < config.strongPenaltySharpnessRatio)
        #expect(config.strongPenaltySharpnessRatio < config.weakPenaltySharpnessRatio)
        #expect(config.clippingFreeFraction < config.clippingFullPenaltyFraction)
        #expect(config.clippingFullPenaltyFraction < config.clippingCriticalFraction)
    }

    @Test func testScoreFreshnessFollowsTheCacheKey() {
        let date = Date(timeIntervalSince1970: 500)
        let score = PhotoQualityScore(
            localIdentifier: "a",
            sourceModificationDate: date,
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1,
            signals: PhotoQualitySignals(globalSharpness: 20)
        )

        #expect(score.isFresh(modificationDate: date, scoringModelVersion: 1, thumbnailConfigVersion: 1))
        #expect(!(score.isFresh(
            modificationDate: date.addingTimeInterval(1),
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1
        )))
        #expect(!(score.isFresh(modificationDate: date, scoringModelVersion: 2, thumbnailConfigVersion: 1)))
        #expect(!(score.isFresh(modificationDate: date, scoringModelVersion: 1, thumbnailConfigVersion: 2)))
    }

    /// Phase 2 writes this flag; scoring must then keep the pre-enhancement
    /// signals instead of measuring Alike's own edit.
    @Test func testEnhancedAssetsAreNotInvalidatedByTheirNewModificationDate() {
        let score = PhotoQualityScore(
            localIdentifier: "a",
            sourceModificationDate: Date(timeIntervalSince1970: 500),
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1,
            signals: PhotoQualitySignals(globalSharpness: 20),
            isAlikeEnhanced: true
        )

        #expect(score.isFresh(
            modificationDate: Date(timeIntervalSince1970: 9_000),
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1
        ))
    }

    /// After the edit these signals are the only surviving measurement of the
    /// original, and no version bump can bring the original pixels back — a
    /// re-score would measure Alike's own enhancement instead.
    @Test func testEnhancedAssetsSurviveAScoringModelVersionBump() {
        let score = PhotoQualityScore(
            localIdentifier: "a",
            sourceModificationDate: Date(timeIntervalSince1970: 500),
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1,
            signals: PhotoQualitySignals(globalSharpness: 20),
            isAlikeEnhanced: true
        )

        #expect(score.isFresh(
            modificationDate: Date(timeIntervalSince1970: 9_000),
            scoringModelVersion: 2,
            thumbnailConfigVersion: 3
        ))
    }
}
