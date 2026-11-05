import Foundation
import Testing
import Core
@testable import Storage

@Suite struct CoreDataPhotoQualityScoreRepositoryTests {
    private let repository: CoreDataPhotoQualityScoreRepository
    private let inMemoryController: PersistenceController
    private let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)

    init() {
        inMemoryController = PersistenceController.preview()
        repository = CoreDataPhotoQualityScoreRepository(persistence: inMemoryController)
    }

    @Test func testSaveAndLoadRoundTripsSignals() async throws {
        try await repository.saveScores([makeScore("photo-1")])

        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        let score = try #require(loaded["photo-1"])

        let eps = 0.000_1
        let dateEps = 0.001
        #expect(abs(score.signals.globalSharpness - 42) <= eps)
        #expect(abs((score.signals.subjectSharpness ?? 0) - 30) <= eps)
        #expect(score.signals.usableFaceSignals.count == 1)
        #expect(abs((score.sourceModificationDate?.timeIntervalSince1970 ?? 0) - modificationDate.timeIntervalSince1970) <= dateEps)
        #expect(!score.isAlikeEnhanced)
    }

    @Test func testCacheHitForUnchangedAssetAndVersions() async throws {
        try await repository.saveScores([makeScore("photo-1")])
        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        let score = try #require(loaded["photo-1"])

        #expect(score.isFresh(
            modificationDate: modificationDate,
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1
        ))
    }

    @Test func testCacheMissOnChangedModificationDate() async throws {
        try await repository.saveScores([makeScore("photo-1")])
        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        let score = try #require(loaded["photo-1"])

        #expect(!(score.isFresh(
            modificationDate: modificationDate.addingTimeInterval(60),
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1
        )))
    }

    @Test func testCacheMissOnChangedScoringModelVersion() async throws {
        try await repository.saveScores([makeScore("photo-1")])
        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        let score = try #require(loaded["photo-1"])

        #expect(!(score.isFresh(
            modificationDate: modificationDate,
            scoringModelVersion: 2,
            thumbnailConfigVersion: 1
        )))
    }

    @Test func testCacheMissOnChangedThumbnailConfigVersion() async throws {
        try await repository.saveScores([makeScore("photo-1")])
        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        let score = try #require(loaded["photo-1"])

        #expect(!(score.isFresh(
            modificationDate: modificationDate,
            scoringModelVersion: 1,
            thumbnailConfigVersion: 2
        )))
    }

    @Test func testSavingTwiceOverwritesInsteadOfDuplicating() async throws {
        try await repository.saveScores([makeScore("photo-1", globalSharpness: 10)])
        try await repository.saveScores([makeScore("photo-1", globalSharpness: 90)])

        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        #expect(loaded.count == 1)
        let eps = 0.000_1
        #expect(abs((loaded["photo-1"]?.signals.globalSharpness ?? 0) - 90) <= eps)
    }

    @Test func testUnknownIdentifiersAreSimplyAbsent() async throws {
        try await repository.saveScores([makeScore("photo-1")])

        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1", "photo-2"])

        #expect(Set(loaded.keys) == ["photo-1"])
    }

    @Test func testDeleteAllScoresClearsTheCache() async throws {
        try await repository.saveScores([makeScore("photo-1"), makeScore("photo-2")])

        try await repository.deleteAllScores()

        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1", "photo-2"])
        #expect(loaded.isEmpty)
    }

    @Test func testEnhancedFlagSurvivesTheRoundTrip() async throws {
        try await repository.saveScores([makeScore("photo-1", isAlikeEnhanced: true)])

        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        let score = try #require(loaded["photo-1"])

        #expect(score.isAlikeEnhanced)
        #expect(score.isFresh(
            modificationDate: modificationDate.addingTimeInterval(3_600),
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1
        ))
    }

    // MARK: - Helpers

    private func makeScore(
        _ localIdentifier: String,
        globalSharpness: Double = 42,
        isAlikeEnhanced: Bool = false
    ) -> PhotoQualityScore {
        PhotoQualityScore(
            localIdentifier: localIdentifier,
            sourceModificationDate: modificationDate,
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1,
            signals: PhotoQualitySignals(
                globalSharpness: globalSharpness,
                subjectSharpness: 30,
                darkClippedFraction: 0.01,
                brightClippedFraction: 0.02,
                subjectLumaStdDev: 0.2,
                noiseEstimate: 0.05,
                faceSignals: [
                    FaceQualitySignal(
                        detectionConfidence: 0.9,
                        boxPixelSize: 120,
                        sharpness: 30,
                        hasClosedEyes: false,
                        isCroppedByFrame: false
                    )
                ],
                pixelArea: 12_000_000
            ),
            scoredAt: Date(timeIntervalSince1970: 1_700_000_500),
            isAlikeEnhanced: isAlikeEnhanced
        )
    }
}
