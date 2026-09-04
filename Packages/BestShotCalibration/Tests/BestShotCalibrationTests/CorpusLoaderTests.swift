import XCTest
@testable import BestShotCalibration
@testable import Core

final class CorpusLoaderTests: XCTestCase {
    private func makeCorpus(
        schemaVersion: Int = BestShotCalibrationCorpus.currentSchemaVersion,
        scoringModelVersion: Int = PhotoQualityScoringConfig.current.scoringModelVersion,
        thumbnailConfigVersion: Int = PhotoQualityScoringConfig.current.thumbnailConfigVersion
    ) -> BestShotCalibrationCorpus {
        BestShotCalibrationCorpus(
            schemaVersion: schemaVersion,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            scoringModelVersion: scoringModelVersion,
            thumbnailConfigVersion: thumbnailConfigVersion,
            entries: [
                BestShotCalibrationCluster(
                    clusterID: "c1",
                    category: .people,
                    candidates: [
                        BestShotCalibrationCandidate(
                            assetID: "a1",
                            signals: PhotoQualitySignals(globalSharpness: 40, pixelArea: 12_000_000),
                            creationDate: Date(timeIntervalSince1970: 1_000),
                            modificationDate: Date(timeIntervalSince1970: 1_000),
                            pixelWidth: 4000,
                            pixelHeight: 3000
                        ),
                    ],
                    humanBestShotID: "a1"
                ),
            ]
        )
    }

    func testRoundTripsThroughTheLoadersEncoderAndDecoder() throws {
        let corpus = makeCorpus()
        let data = try CorpusLoader.makeEncoder().encode(corpus)
        let result = try CorpusLoader.load(data: data)

        XCTAssertEqual(result.corpus, corpus)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testTooNewSchemaVersionThrows() throws {
        let corpus = makeCorpus(schemaVersion: BestShotCalibrationCorpus.currentSchemaVersion + 1)
        let data = try CorpusLoader.makeEncoder().encode(corpus)

        XCTAssertThrowsError(try CorpusLoader.load(data: data)) { error in
            guard let loaderError = error as? CorpusLoader.LoaderError else {
                return XCTFail("Expected a LoaderError, got \(error)")
            }
            XCTAssertEqual(
                loaderError,
                .schemaTooNew(
                    found: BestShotCalibrationCorpus.currentSchemaVersion + 1,
                    supported: BestShotCalibrationCorpus.currentSchemaVersion
                )
            )
        }
    }

    func testThumbnailConfigVersionMismatchProducesAWarning() throws {
        let mismatchedVersion = PhotoQualityScoringConfig.current.thumbnailConfigVersion + 1
        let corpus = makeCorpus(thumbnailConfigVersion: mismatchedVersion)
        let data = try CorpusLoader.makeEncoder().encode(corpus)

        let result = try CorpusLoader.load(data: data, currentConfig: .current)

        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.warnings[0].contains("thumbnailConfigVersion"))
    }

    func testMatchingThumbnailConfigVersionProducesNoWarning() throws {
        let corpus = makeCorpus()
        let data = try CorpusLoader.makeEncoder().encode(corpus)

        let result = try CorpusLoader.load(data: data, currentConfig: .current)

        XCTAssertTrue(result.warnings.isEmpty)
    }
}
