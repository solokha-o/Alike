import XCTest
import Core
@testable import Storage

final class CoreDataPhotoQualityScoreRepositoryTests: XCTestCase {
    private var repository: CoreDataPhotoQualityScoreRepository!
    private var inMemoryController: PersistenceController!
    private let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        inMemoryController = PersistenceController.preview()
        repository = CoreDataPhotoQualityScoreRepository(persistence: inMemoryController)
    }

    override func tearDown() async throws {
        repository = nil
        inMemoryController = nil
    }

    func testSaveAndLoadRoundTripsSignals() async throws {
        try await repository.saveScores([makeScore("photo-1")])

        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        let score = try XCTUnwrap(loaded["photo-1"])

        XCTAssertEqual(score.signals.globalSharpness, 42, accuracy: 0.000_1)
        XCTAssertEqual(score.signals.subjectSharpness ?? 0, 30, accuracy: 0.000_1)
        XCTAssertEqual(score.signals.usableFaceSignals.count, 1)
        XCTAssertEqual(score.sourceModificationDate?.timeIntervalSince1970 ?? 0,
                       modificationDate.timeIntervalSince1970,
                       accuracy: 0.001)
        XCTAssertFalse(score.isAlikeEnhanced)
    }

    func testCacheHitForUnchangedAssetAndVersions() async throws {
        try await repository.saveScores([makeScore("photo-1")])
        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        let score = try XCTUnwrap(loaded["photo-1"])

        XCTAssertTrue(score.isFresh(
            modificationDate: modificationDate,
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1
        ))
    }

    func testCacheMissOnChangedModificationDate() async throws {
        try await repository.saveScores([makeScore("photo-1")])
        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        let score = try XCTUnwrap(loaded["photo-1"])

        XCTAssertFalse(score.isFresh(
            modificationDate: modificationDate.addingTimeInterval(60),
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1
        ))
    }

    func testCacheMissOnChangedScoringModelVersion() async throws {
        try await repository.saveScores([makeScore("photo-1")])
        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        let score = try XCTUnwrap(loaded["photo-1"])

        XCTAssertFalse(score.isFresh(
            modificationDate: modificationDate,
            scoringModelVersion: 2,
            thumbnailConfigVersion: 1
        ))
    }

    func testCacheMissOnChangedThumbnailConfigVersion() async throws {
        try await repository.saveScores([makeScore("photo-1")])
        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        let score = try XCTUnwrap(loaded["photo-1"])

        XCTAssertFalse(score.isFresh(
            modificationDate: modificationDate,
            scoringModelVersion: 1,
            thumbnailConfigVersion: 2
        ))
    }

    func testSavingTwiceOverwritesInsteadOfDuplicating() async throws {
        try await repository.saveScores([makeScore("photo-1", globalSharpness: 10)])
        try await repository.saveScores([makeScore("photo-1", globalSharpness: 90)])

        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded["photo-1"]?.signals.globalSharpness ?? 0, 90, accuracy: 0.000_1)
    }

    func testUnknownIdentifiersAreSimplyAbsent() async throws {
        try await repository.saveScores([makeScore("photo-1")])

        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1", "photo-2"])

        XCTAssertEqual(Set(loaded.keys), ["photo-1"])
    }

    func testDeleteAllScoresClearsTheCache() async throws {
        try await repository.saveScores([makeScore("photo-1"), makeScore("photo-2")])

        try await repository.deleteAllScores()

        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1", "photo-2"])
        XCTAssertTrue(loaded.isEmpty)
    }

    func testEnhancedFlagSurvivesTheRoundTrip() async throws {
        try await repository.saveScores([makeScore("photo-1", isAlikeEnhanced: true)])

        let loaded = try await repository.loadScores(localIdentifiers: ["photo-1"])
        let score = try XCTUnwrap(loaded["photo-1"])

        XCTAssertTrue(score.isAlikeEnhanced)
        XCTAssertTrue(score.isFresh(
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
