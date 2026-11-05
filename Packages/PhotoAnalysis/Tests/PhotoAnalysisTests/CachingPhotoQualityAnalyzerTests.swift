import Core
import Foundation
import Photos
import Testing
@testable import PhotoAnalysis

@Suite struct CachingPhotoQualityAnalyzerTests {
    private let config = PhotoQualityScoringConfig.current
    private let modificationDate = Date(timeIntervalSince1970: 1_000)

    @Test func testFreshCacheEntriesAreNotMeasuredAgain() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([makeCachedScore("cached", globalSharpness: 33)])
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(repository: repository, analyzer: inner, config: config)

        let scores = try await analyzer.scores(for: [TestPHAsset(identifier: "cached")])

        let measured = await inner.receivedIdentifiers
        #expect(measured.isEmpty)
        #expect(scores.map(\.localIdentifier) == ["cached"])
        let eps = 0.000_1
        #expect(abs((scores.first?.signals.globalSharpness ?? 0) - 33) <= eps)
    }

    @Test func testOnlyCacheMissesAreMeasuredAndWrittenBack() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([makeCachedScore("cached", globalSharpness: 33)])
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(repository: repository, analyzer: inner, config: config)

        let scores = try await analyzer.scores(for: [
            TestPHAsset(identifier: "cached"),
            TestPHAsset(identifier: "fresh")
        ])

        let measured = await inner.receivedIdentifiers
        #expect(measured == ["fresh"])
        #expect(scores.map(\.localIdentifier) == ["cached", "fresh"])
        let stored = try await repository.loadScores(localIdentifiers: ["fresh"])
        #expect(stored["fresh"] != nil)
    }

    @Test func testAChangedPhotoIsMeasuredAgain() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([makeCachedScore("edited", globalSharpness: 33)])
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(repository: repository, analyzer: inner, config: config)

        _ = try await analyzer.scores(for: [
            TestPHAsset(identifier: "edited", modificationDate: modificationDate.addingTimeInterval(60))
        ])

        let measured = await inner.receivedIdentifiers
        #expect(measured == ["edited"])
    }

    @Test func testAStaleScoringModelVersionIsMeasuredAgain() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([
            makeCachedScore("old-model", globalSharpness: 33, scoringModelVersion: config.scoringModelVersion - 1)
        ])
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(repository: repository, analyzer: inner, config: config)

        _ = try await analyzer.scores(for: [TestPHAsset(identifier: "old-model")])

        let measured = await inner.receivedIdentifiers
        #expect(measured == ["old-model"])
    }

    /// Phase 2 flags the assets Alike itself enhanced. Re-scoring them would
    /// measure our own edit, lifting the score of the very photo whose defects
    /// the ranking was supposed to see.
    @Test func testAnAlikeEnhancedPhotoIsNotRescoredAndKeepsItsPreEnhancementSignals() async throws {
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
        #expect(measured.isEmpty)
        let eps = 0.000_1
        #expect(abs((scores.first?.signals.globalSharpness ?? 0) - 21) <= eps)
        #expect(scores.first?.isAlikeEnhanced == true)
    }

    /// The pre-enhancement signals survive only while our edit is the edit on
    /// the photo. It still is here, so nothing is re-measured.
    @Test func testAnEnhancedPhotoStillCarryingOurEditKeepsItsSignals() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([
            makeCachedScore("enhanced", globalSharpness: 21, isAlikeEnhanced: true)
        ])
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(
            repository: repository,
            analyzer: inner,
            config: config,
            enhancementAvailability: { _ in .enhanced }
        )

        let scores = try await analyzer.scores(for: [
            TestPHAsset(identifier: "enhanced", modificationDate: modificationDate.addingTimeInterval(3_600))
        ])

        let measured = await inner.receivedIdentifiers
        #expect(measured.isEmpty)
        let eps = 0.000_1
        #expect(abs((scores.first?.signals.globalSharpness ?? 0) - 21) <= eps)
    }

    /// The user edited the photo in another app afterwards. The cached signals
    /// describe pixels nobody will see again, so the ranker measures what is
    /// there now instead of ranking on a stale original for good.
    @Test func testAnEnhancedPhotoEditedElsewhereIsMeasuredAgain() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([
            makeCachedScore("enhanced", globalSharpness: 21, isAlikeEnhanced: true)
        ])
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(
            repository: repository,
            analyzer: inner,
            config: config,
            enhancementAvailability: { _ in .editedElsewhere }
        )

        let scores = try await analyzer.scores(for: [
            TestPHAsset(identifier: "enhanced", modificationDate: modificationDate.addingTimeInterval(3_600))
        ])

        let measured = await inner.receivedIdentifiers
        #expect(measured == ["enhanced"])
        let eps = 0.000_1
        #expect(abs((scores.first?.signals.globalSharpness ?? 0) - 50) <= eps)
    }

    /// Our edit was undone in Photos, so the photo is back to its original and
    /// the flagged row no longer describes anything special.
    @Test func testAnEnhancedPhotoRevertedInPhotosIsMeasuredAgain() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([
            makeCachedScore("enhanced", globalSharpness: 21, isAlikeEnhanced: true)
        ])
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(
            repository: repository,
            analyzer: inner,
            config: config,
            enhancementAvailability: { _ in .available }
        )

        _ = try await analyzer.scores(for: [TestPHAsset(identifier: "enhanced")])

        let measured = await inner.receivedIdentifiers
        #expect(measured == ["enhanced"])
    }

    /// An asset the library will not answer for is "cannot tell", not "the edit
    /// is gone": throwing away the only measurement of the original over a
    /// temporary read failure is worse than keeping it.
    @Test func testAnUnreadableEnhancedPhotoKeepsItsSignals() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([
            makeCachedScore("enhanced", globalSharpness: 21, isAlikeEnhanced: true)
        ])
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(
            repository: repository,
            analyzer: inner,
            config: config,
            enhancementAvailability: { _ in .unavailable }
        )

        let scores = try await analyzer.scores(for: [TestPHAsset(identifier: "enhanced")])

        let measured = await inner.receivedIdentifiers
        #expect(measured.isEmpty)
        let eps = 0.000_1
        #expect(abs((scores.first?.signals.globalSharpness ?? 0) - 21) <= eps)
    }

    /// Only the flagged rows pay for the extra question.
    @Test func testAnOrdinaryCachedPhotoIsNotAskedAboutItsEdit() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([makeCachedScore("cached", globalSharpness: 33)])
        let inner = RecordingQualityAnalyzer()
        let asked = AskedIdentifiers()
        let analyzer = CachingPhotoQualityAnalyzer(
            repository: repository,
            analyzer: inner,
            config: config,
            enhancementAvailability: { identifier in
                await asked.record(identifier)
                return .available
            }
        )

        _ = try await analyzer.scores(for: [
            TestPHAsset(identifier: "cached"),
            TestPHAsset(identifier: "fresh")
        ])

        let identifiers = await asked.identifiers
        #expect(identifiers.isEmpty)
    }

    /// A failed measurement is a moment, not a fact about the photo: caching it
    /// as fresh would mean one offline moment removes the asset from ranking
    /// for good.
    @Test func testATransientFailureIsRetriedOnTheNextRun() async throws {
        let repository = MockPhotoQualityScoreRepository()
        let failing = FixedQualityAnalyzer(signals: .failed(.assetUnavailable))
        let asset = TestPHAsset(identifier: "offline")

        let firstRun = try await CachingPhotoQualityAnalyzer(
            repository: repository,
            analyzer: failing,
            config: config
        ).scores(for: [asset])
        #expect(firstRun.first?.signals.analysisFailure == .assetUnavailable)

        let cached = try await repository.loadScores(localIdentifiers: ["offline"])
        #expect(cached.isEmpty, "A failure must not occupy the cache")

        let succeeding = RecordingQualityAnalyzer()
        let secondRun = try await CachingPhotoQualityAnalyzer(
            repository: repository,
            analyzer: succeeding,
            config: config
        ).scores(for: [asset])

        let measured = await succeeding.receivedIdentifiers
        #expect(measured == ["offline"])
        #expect(secondRun.first?.signals.isUsable == true)
    }

    @Test func testAFailingCacheStillProducesScores() async throws {
        struct CacheError: Error {}
        let repository = MockPhotoQualityScoreRepository()
        await repository.setLoadScoresError(CacheError())
        let inner = RecordingQualityAnalyzer()
        let analyzer = CachingPhotoQualityAnalyzer(repository: repository, analyzer: inner, config: config)

        let scores = try await analyzer.scores(for: [TestPHAsset(identifier: "a")])

        #expect(scores.map(\.localIdentifier) == ["a"])
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

/// Always answers with the same signals, whatever it is handed.
private actor FixedQualityAnalyzer: PhotoQualityAnalyzing {
    private let signals: PhotoQualitySignals

    init(signals: PhotoQualitySignals) {
        self.signals = signals
    }

    func scores(for assets: [PHAsset]) async throws -> [PhotoQualityScore] {
        let config = PhotoQualityScoringConfig.current
        return assets.map { asset in
            PhotoQualityScore(
                localIdentifier: asset.localIdentifier,
                sourceModificationDate: asset.modificationDate,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: signals
            )
        }
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

/// Records which assets the analyzer asked the library about.
private actor AskedIdentifiers {
    private(set) var identifiers: [String] = []

    func record(_ identifier: String) {
        identifiers.append(identifier)
    }
}
