import XCTest
@testable import Core

final class BestShotCalibrationCorpusTests: XCTestCase {
    private func makeCorpus() -> BestShotCalibrationCorpus {
        let withFaces = BestShotCalibrationCluster(
            clusterID: "cluster-faces",
            category: .people,
            candidates: [
                BestShotCalibrationCandidate(
                    assetID: "asset-1",
                    signals: PhotoQualitySignals(
                        globalSharpness: 60,
                        subjectSharpness: 55,
                        darkClippedFraction: 0.01,
                        brightClippedFraction: 0.02,
                        subjectLumaStdDev: 0.3,
                        noiseEstimate: 0.1,
                        faceSignals: [
                            FaceQualitySignal(
                                detectionConfidence: 0.95,
                                boxPixelSize: 140,
                                sharpness: 55,
                                hasClosedEyes: false,
                                isCroppedByFrame: false
                            )
                        ],
                        pixelArea: 12_000_000
                    ),
                    creationDate: Date(timeIntervalSince1970: 1_000),
                    modificationDate: Date(timeIntervalSince1970: 1_000),
                    pixelWidth: 4000,
                    pixelHeight: 3000,
                    isFavorite: true
                ),
                BestShotCalibrationCandidate(
                    assetID: "asset-2",
                    signals: PhotoQualitySignals(globalSharpness: 20, pixelArea: 12_000_000),
                    creationDate: Date(timeIntervalSince1970: 1_001),
                    modificationDate: nil,
                    pixelWidth: 4000,
                    pixelHeight: 3000,
                    isFavorite: false
                )
            ],
            humanBestShotID: "asset-1"
        )

        let withoutFaces = BestShotCalibrationCluster(
            clusterID: "cluster-landscape",
            candidates: [
                BestShotCalibrationCandidate(
                    assetID: "asset-3",
                    signals: PhotoQualitySignals(globalSharpness: 40, pixelArea: 8_000_000),
                    pixelWidth: 3000,
                    pixelHeight: 2000
                ),
                BestShotCalibrationCandidate(
                    assetID: "asset-4",
                    signals: PhotoQualitySignals(globalSharpness: 45, pixelArea: 8_000_000),
                    pixelWidth: 3000,
                    pixelHeight: 2000
                )
            ],
            humanBestShotID: "asset-4"
        )

        return BestShotCalibrationCorpus(
            exportedAt: Date(timeIntervalSince1970: 2_000),
            scoringModelVersion: 1,
            thumbnailConfigVersion: 1,
            entries: [withFaces, withoutFaces]
        )
    }

    func testCodableRoundTrip() throws {
        let corpus = makeCorpus()
        let data = try JSONEncoder().encode(corpus)
        let decoded = try JSONDecoder().decode(BestShotCalibrationCorpus.self, from: data)

        XCTAssertEqual(decoded, corpus)
        XCTAssertEqual(decoded.entries.count, 2)
        XCTAssertEqual(decoded.entries[0].category, .people)
        XCTAssertNil(decoded.entries[1].category)
        XCTAssertEqual(decoded.entries[0].candidates.first?.signals.faceSignals?.count, 1)
        XCTAssertNil(decoded.entries[1].candidates.first?.signals.faceSignals)
    }

    func testDecodingAHigherUnknownSchemaVersionStillSucceeds() throws {
        // Additive fields are how the schema is meant to evolve: a future
        // exporter can add new optional keys without breaking today's reader,
        // as long as it keeps decoding the fields this version knows about.
        let json = """
        {
            "schemaVersion": 99,
            "exportedAt": 2000,
            "scoringModelVersion": 1,
            "thumbnailConfigVersion": 1,
            "entries": [
                {
                    "clusterID": "cluster-future",
                    "candidates": [
                        {
                            "assetID": "asset-1",
                            "signals": {
                                "globalSharpness": 50,
                                "darkClippedFraction": 0,
                                "brightClippedFraction": 0,
                                "subjectLumaStdDev": 0.2,
                                "noiseEstimate": 0.1,
                                "pixelArea": 1000000
                            },
                            "pixelWidth": 100,
                            "pixelHeight": 100,
                            "isFavorite": false
                        }
                    ],
                    "humanBestShotID": "asset-1"
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let corpus = try decoder.decode(BestShotCalibrationCorpus.self, from: json)

        XCTAssertEqual(corpus.schemaVersion, 99)
        XCTAssertEqual(corpus.entries.first?.clusterID, "cluster-future")
    }

    func testSnapshotsAndScoresAreKeyedByAssetID() {
        let cluster = makeCorpus().entries[0]

        let snapshots = cluster.snapshots
        XCTAssertEqual(Set(snapshots.map(\.localIdentifier)), ["asset-1", "asset-2"])

        let scores = cluster.scores(scoringModelVersion: 1, thumbnailConfigVersion: 1)
        XCTAssertEqual(Set(scores.keys), ["asset-1", "asset-2"])
        XCTAssertEqual(scores["asset-1"]?.signals.globalSharpness, 60)
        XCTAssertEqual(scores["asset-1"]?.scoringModelVersion, 1)
        XCTAssertEqual(scores["asset-1"]?.isAlikeEnhanced, false)
    }
}
