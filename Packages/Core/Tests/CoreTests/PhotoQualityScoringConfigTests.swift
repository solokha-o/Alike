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
        XCTAssertEqual(PhotoQualityScoringConfig.current.thumbnailConfigVersion, 1)
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
