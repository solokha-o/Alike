import Core
import Foundation
import Photos
import XCTest
@testable import PhotoAnalysis

final class CachingPhotoQualityAnalyzerTests: XCTestCase {
    private let config = PhotoQualityScoringConfig.current
    private let modificationDate = Date(timeIntervalSince1970: 1_000)

    func testFreshCacheEntriesAreNotMeasuredAgain() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([makeCachedScore("cached", globalSharpness: 33)])
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(repository: repository, analyzer: inner, config: config)

        let scores = try await analyzer.scores(for: [TestPHAsset(identifier: "cached")])

        let measured = await inner.receivedIdentifiers
        XCTAssertTrue(measured.isEmpty)
        XCTAssertEqual(scores.map(\.localIdentifier), ["cached"])
        XCTAssertEqual(scores.first?.signals.globalSharpness ?? 0, 33, accuracy: 0.000_1)
    }

    func testOnlyCacheMissesAreMeasuredAndWrittenBack() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([makeCachedScore("cached", globalSharpness: 33)])
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(repository: repository, analyzer: inner, config: config)

        let scores = try await analyzer.scores(for: [
            TestPHAsset(identifier: "cached"),
            TestPHAsset(identifier: "fresh")
        ])

        let measured = await inner.receivedIdentifiers
        XCTAssertEqual(measured, ["fresh"])
        XCTAssertEqual(scores.map(\.localIdentifier), ["cached", "fresh"])
        let stored = try await repository.loadScores(localIdentifiers: ["fresh"])
        XCTAssertNotNil(stored["fresh"])
    }

    func testAChangedPhotoIsMeasuredAgain() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([makeCachedScore("edited", globalSharpness: 33)])
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(repository: repository, analyzer: inner, config: config)

        _ = try await analyzer.scores(for: [
            TestPHAsset(identifier: "edited", modificationDate: modificationDate.addingTimeInterval(60))
        ])

        let measured = await inner.receivedIdentifiers
        XCTAssertEqual(measured, ["edited"])
    }

    func testAStaleScoringModelVersionIsMeasuredAgain() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([
            makeCachedScore("old-model", globalSharpness: 33, scoringModelVersion: config.scoringModelVersion - 1)
        ])
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(repository: repository, analyzer: inner, config: config)

        _ = try await analyzer.scores(for: [TestPHAsset(identifier: "old-model")])

        let measured = await inner.receivedIdentifiers
        XCTAssertEqual(measured, ["old-model"])
    }

    /// Phase 2 flags the assets Alike itself enhanced. Re-scoring them would
    /// measure our own edit, lifting the score of the very photo whose defects
    /// the ranking was supposed to see.
    func testAnAlikeEnhancedPhotoIsNotRescoredAndKeepsItsPreEnhancementSignals() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([
            makeCachedScore("enhanced", globalSharpness: 21, isAlikeEnhanced: true)
        ])
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(repository: repository, analyzer: inner, config: config)

        // The enhancement rewrote the asset's modification date.
        let scores = try await analyzer.scores(for: [
            TestPHAsset(identifier: "enhanced", modificationDate: modificationDate.addingTimeInterval(3_600))
        ])

        let measured = await inner.receivedIdentifiers
        XCTAssertTrue(measured.isEmpty)
        XCTAssertEqual(scores.first?.signals.globalSharpness ?? 0, 21, accuracy: 0.000_1)
        XCTAssertEqual(scores.first?.isAlikeEnhanced, true)
    }

    func testAFailingCacheStillProducesScores() async throws {
        struct CacheError: Error {}
        let repository = MockPhotoQualityScoreRepository()
        await repository.setLoadScoresError(CacheError())
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(repository: repository, analyzer: inner, config: config)

        let scores = try await analyzer.scores(for: [TestPHAsset(identifier: "a")])

        XCTAssertEqual(scores.map(\.localIdentifier), ["a"])
    }

    // MARK: - Helpers

    private func makeCachedScore(
        _ localIdentifier: String,
        globalSharpness: Double,
        scoringModelVersion: Int? = nil,
        isAlikeEnhanced: Bool = false
    ) -> PhotoQualityScore {
        PhotoQualityScore(
            localIdentifier: localIdentifier,
            sourceModificationDate: modificationDate,
            scoringModelVersion: scoringModelVersion ?? config.scoringModelVersion,
            thumbnailConfigVersion: config.thumbnailConfigVersion,
            signals: PhotoQualitySignals(globalSharpness: globalSharpness, pixelArea: 12_000_000),
            isAlikeEnhanced: isAlikeEnhanced
        )
    }
}

/// Records what it was asked to measure and answers with trivial signals.
private actor RecordingQualityAnalyzer: PhotoQualityAnalyzing {
    private(set) var receivedIdentifiers: [String] = []

    func scores(for assets: [PHAsset]) async throws -> [PhotoQualityScore] {
        let config = PhotoQualityScoringConfig.current
        receivedIdentifiers.append(contentsOf: assets.map(\.localIdentifier))
        return assets.map { asset in
            PhotoQualityScore(
                localIdentifier: asset.localIdentifier,
                sourceModificationDate: asset.modificationDate,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(globalSharpness: 50, pixelArea: 12_000_000)
            )
        }
    }
}
