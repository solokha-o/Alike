#if DEBUG
import XCTest
import Core
@testable import Settings

@MainActor
final class BestShotCalibrationLabelingViewModelTests: XCTestCase {
    private func makeViewModel(defaults: UserDefaults) -> BestShotCalibrationLabelingViewModel {
        BestShotCalibrationLabelingViewModel(
            clusterRepository: MockPhotoClusterRepository(),
            qualityAnalyzer: MockPhotoQualityAnalyzer(),
            defaults: defaults
        )
    }

    private func makeEphemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "BestShotCalibrationLabelingViewModelTests-\(UUID().uuidString)")!
    }

    private func makePreparedCluster(
        clusterID: UUID = UUID(),
        localIdentifiers: [String]
    ) -> BestShotCalibrationPreparedCluster {
        BestShotCalibrationPreparedCluster(
            clusterID: clusterID,
            candidates: localIdentifiers.map { identifier in
                BestShotCalibrationPreparedCandidate(
                    localIdentifier: identifier,
                    signals: PhotoQualitySignals(globalSharpness: 42),
                    creationDate: Date(timeIntervalSince1970: 1_700_000_000),
                    modificationDate: Date(timeIntervalSince1970: 1_700_000_100),
                    pixelWidth: 3024,
                    pixelHeight: 4032,
                    isFavorite: false
                )
            }
        )
    }

    func testExportedCorpusDecodesAndHumanBestShotMatchesACandidate() throws {
        let defaults = makeEphemeralDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        let clusterID = UUID()
        let prepared = makePreparedCluster(
            clusterID: clusterID,
            localIdentifiers: ["real-local-id-1", "real-local-id-2"]
        )
        viewModel.setPreparedClusterForTesting(prepared)

        viewModel.recordLabel(
            clusterID: clusterID,
            bestShotAssetID: "real-local-id-2",
            category: .people
        )

        XCTAssertEqual(viewModel.labelledCount, 1)

        let data = try viewModel.exportJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let corpus = try decoder.decode(BestShotCalibrationCorpus.self, from: data)

        XCTAssertEqual(corpus.entries.count, 1)
        let entry = try XCTUnwrap(corpus.entries.first)
        XCTAssertEqual(entry.category, .people)
        XCTAssertEqual(entry.candidates.count, 2)
        XCTAssertTrue(entry.candidates.contains { $0.assetID == entry.humanBestShotID })
    }

    func testDifferentSaltsProduceDifferentAssetIDsForSameLocalIdentifier() throws {
        let localIdentifier = "shared-local-identifier"
        let clusterID = UUID()

        let viewModelA = makeViewModel(defaults: makeEphemeralDefaults())
        viewModelA.setPreparedClusterForTesting(
            makePreparedCluster(clusterID: clusterID, localIdentifiers: [localIdentifier])
        )
        viewModelA.recordLabel(clusterID: clusterID, bestShotAssetID: localIdentifier, category: nil)

        let viewModelB = makeViewModel(defaults: makeEphemeralDefaults())
        viewModelB.setPreparedClusterForTesting(
            makePreparedCluster(clusterID: clusterID, localIdentifiers: [localIdentifier])
        )
        viewModelB.recordLabel(clusterID: clusterID, bestShotAssetID: localIdentifier, category: nil)

        let corpusA = try JSONDecoder.calibration.decode(
            BestShotCalibrationCorpus.self,
            from: viewModelA.exportJSON()
        )
        let corpusB = try JSONDecoder.calibration.decode(
            BestShotCalibrationCorpus.self,
            from: viewModelB.exportJSON()
        )

        let assetIDA = try XCTUnwrap(corpusA.entries.first?.humanBestShotID)
        let assetIDB = try XCTUnwrap(corpusB.entries.first?.humanBestShotID)
        XCTAssertNotEqual(assetIDA, assetIDB)
    }

    func testExportedBytesContainNoPhotoKitLocalIdentifier() throws {
        let defaults = makeEphemeralDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        let clusterID = UUID()
        let secretLocalIdentifier = "8F2C1A4B-0000-1111-2222-ABCDEF012345/L0/001"
        let prepared = makePreparedCluster(
            clusterID: clusterID,
            localIdentifiers: [secretLocalIdentifier, "another-local-id"]
        )
        viewModel.setPreparedClusterForTesting(prepared)
        viewModel.recordLabel(
            clusterID: clusterID,
            bestShotAssetID: secretLocalIdentifier,
            category: .night
        )

        let data = try viewModel.exportJSON()
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(text.contains(secretLocalIdentifier))
        XCTAssertFalse(text.contains("another-local-id"))
    }

    func testPersistedSessionRoundTripsLocalIdentifierMap() throws {
        let defaults = makeEphemeralDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        let clusterID = UUID()
        let prepared = makePreparedCluster(
            clusterID: clusterID,
            localIdentifiers: ["real-local-id-1", "real-local-id-2"]
        )
        viewModel.setPreparedClusterForTesting(prepared)
        viewModel.recordLabel(clusterID: clusterID, bestShotAssetID: "real-local-id-2", category: nil)

        let data = try viewModel.exportJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try XCTUnwrap(try decoder.decode(BestShotCalibrationCorpus.self, from: data).entries.first)

        // Reload a fresh view model from the same UserDefaults suite, as the
        // screen does across a relaunch, and confirm the localIdentifier map
        // survived the round trip through the persisted session.
        let resumedViewModel = makeViewModel(defaults: defaults)
        let resumedMap = resumedViewModel.candidateLocalIdentifiersForTesting(clusterID: entry.clusterID)
        XCTAssertEqual(resumedMap, [
            entry.candidates[0].assetID: "real-local-id-1",
            entry.candidates[1].assetID: "real-local-id-2",
        ])
    }

    func testExportedBytesContainNoLocalIdentifierWhenTheResumeMapIsPopulated() throws {
        let defaults = makeEphemeralDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        let clusterID = UUID()
        let secretLocalIdentifier = "8F2C1A4B-0000-1111-2222-ABCDEF012345/L0/001"
        let prepared = makePreparedCluster(
            clusterID: clusterID,
            localIdentifiers: [secretLocalIdentifier, "another-local-id"]
        )
        viewModel.setPreparedClusterForTesting(prepared)
        viewModel.recordLabel(
            clusterID: clusterID,
            bestShotAssetID: secretLocalIdentifier,
            category: .night
        )

        // The resume buffer now holds the localIdentifier map (asserted by
        // testPersistedSessionRoundTripsLocalIdentifierMap); exportJSON()
        // must still never surface it.
        let data = try viewModel.exportJSON()
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(text.contains(secretLocalIdentifier))
        XCTAssertFalse(text.contains("another-local-id"))
        XCTAssertFalse(text.contains("candidateLocalIdentifiers"))
        XCTAssertFalse(text.contains("localIdentifier"))
    }

    func testRehashingAStoredLocalIdentifierReproducesTheSameAnonymizedAssetID() throws {
        let defaults = makeEphemeralDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        let clusterID = UUID()
        let localIdentifier = "real-local-id-for-rehash"
        let prepared = makePreparedCluster(clusterID: clusterID, localIdentifiers: [localIdentifier])
        viewModel.setPreparedClusterForTesting(prepared)
        viewModel.recordLabel(clusterID: clusterID, bestShotAssetID: localIdentifier, category: nil)

        let corpus = try JSONDecoder.calibration.decode(
            BestShotCalibrationCorpus.self,
            from: viewModel.exportJSON()
        )
        let recordedAssetID = try XCTUnwrap(corpus.entries.first?.humanBestShotID)

        // Re-hashing the same localIdentifier with the session's persisted
        // salt must reproduce the exact assetID recorded at label time —
        // the property remeasureCorpus() relies on to keep assetIDs stable.
        XCTAssertEqual(viewModel.anonymizedAssetIDForTesting(localIdentifier), recordedAssetID)
    }

    func testResetClearsBufferAndProducesEmptyCorpus() throws {
        let defaults = makeEphemeralDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        let clusterID = UUID()
        viewModel.setPreparedClusterForTesting(
            makePreparedCluster(clusterID: clusterID, localIdentifiers: ["a", "b"])
        )
        viewModel.recordLabel(clusterID: clusterID, bestShotAssetID: "a", category: nil)
        XCTAssertEqual(viewModel.labelledCount, 1)

        viewModel.reset()
        XCTAssertEqual(viewModel.labelledCount, 0)
        XCTAssertNil(viewModel.candidateLocalIdentifiersForTesting(clusterID: clusterID.uuidString))

        let corpus = try JSONDecoder.calibration.decode(
            BestShotCalibrationCorpus.self,
            from: viewModel.exportJSON()
        )
        XCTAssertTrue(corpus.entries.isEmpty)
    }
}

private extension JSONDecoder {
    static var calibration: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
#endif
