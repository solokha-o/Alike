import Foundation
import Testing
@testable import BestShotCalibration
@testable import Core

@Suite struct CorpusLoaderTests {
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

    @Test func testRoundTripsThroughTheLoadersEncoderAndDecoder() throws {
        let corpus = makeCorpus()
        let data = try CorpusLoader.makeEncoder().encode(corpus)
        let result = try CorpusLoader.load(data: data)

        #expect(result.corpus == corpus)
        #expect(result.warnings.isEmpty)
    }

    @Test func testTooNewSchemaVersionThrows() throws {
        let corpus = makeCorpus(schemaVersion: BestShotCalibrationCorpus.currentSchemaVersion + 1)
        let data = try CorpusLoader.makeEncoder().encode(corpus)

        #expect(
            throws: CorpusLoader.LoaderError.schemaTooNew(
                found: BestShotCalibrationCorpus.currentSchemaVersion + 1,
                supported: BestShotCalibrationCorpus.currentSchemaVersion
            )
        ) {
            try CorpusLoader.load(data: data)
        }
    }

    @Test func testThumbnailConfigVersionMismatchProducesAWarning() throws {
        let mismatchedVersion = PhotoQualityScoringConfig.current.thumbnailConfigVersion + 1
        let corpus = makeCorpus(thumbnailConfigVersion: mismatchedVersion)
        let data = try CorpusLoader.makeEncoder().encode(corpus)

        let result = try CorpusLoader.load(data: data, currentConfig: .current)

        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].contains("thumbnailConfigVersion"))
    }

    @Test func testMatchingThumbnailConfigVersionProducesNoWarning() throws {
        let corpus = makeCorpus()
        let data = try CorpusLoader.makeEncoder().encode(corpus)

        let result = try CorpusLoader.load(data: data, currentConfig: .current)

        #expect(result.warnings.isEmpty)
    }
}
