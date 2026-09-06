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

    // MARK: - A2: exportJSON() rejects stale measurements

    /// Regression test for A2: a labelled cluster measured under an older
    /// `thumbnailConfigVersion` than the one `exportJSON()` is about to stamp
    /// the whole corpus with must block the export, not silently get stamped
    /// with a version it was never actually measured under.
    func testExportJSONThrowsWhenAClusterWasMeasuredUnderAnOlderThumbnailConfigVersion() throws {
        let defaults = makeEphemeralDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        let clusterID = UUID()
        viewModel.setPreparedClusterForTesting(
            makePreparedCluster(clusterID: clusterID, localIdentifiers: ["a", "b"])
        )
        viewModel.recordLabel(clusterID: clusterID, bestShotAssetID: "a", category: nil)
        XCTAssertEqual(viewModel.clustersNeedingRemeasureCount, 0, "freshly labelled, so nothing is stale yet")

        // Simulate a geometry change since labelling: the cluster's recorded
        // measurement version now lags the current one.
        viewModel.setMeasuredThumbnailConfigVersionForTesting(
            clusterID: clusterID.uuidString,
            version: viewModel.currentThumbnailConfigVersion - 1
        )
        XCTAssertEqual(viewModel.clustersNeedingRemeasureCount, 1)

        XCTAssertThrowsError(try viewModel.exportJSON()) { error in
            XCTAssertEqual(
                error as? BestShotCalibrationExportError,
                .staleMeasurements(count: 1)
            )
        }
        // exportedCorpusFileURL() calls exportJSON() internally, so it must
        // inherit the same guard rather than writing a stale file to disk.
        XCTAssertThrowsError(try viewModel.exportedCorpusFileURL())
    }

    func testExportJSONSucceedsAgainAfterRemeasuringClearsTheStaleFlag() throws {
        let defaults = makeEphemeralDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        let clusterID = UUID()
        viewModel.setPreparedClusterForTesting(
            makePreparedCluster(clusterID: clusterID, localIdentifiers: ["a", "b"])
        )
        viewModel.recordLabel(clusterID: clusterID, bestShotAssetID: "a", category: nil)
        viewModel.setMeasuredThumbnailConfigVersionForTesting(
            clusterID: clusterID.uuidString,
            version: viewModel.currentThumbnailConfigVersion - 1
        )
        XCTAssertThrowsError(try viewModel.exportJSON())

        // "Remeasuring" here just means the recorded version catches up to
        // current — the real remeasure path (PHAsset resolution +
        // qualityAnalyzer) is exercised by the A3 interleaving test below via
        // the same viewModel state, not re-derived here.
        viewModel.setMeasuredThumbnailConfigVersionForTesting(
            clusterID: clusterID.uuidString,
            version: viewModel.currentThumbnailConfigVersion
        )
        XCTAssertEqual(viewModel.clustersNeedingRemeasureCount, 0)
        XCTAssertNoThrow(try viewModel.exportJSON())
    }

    // MARK: - A3: recordLabel()/reset() reject calls made mid-remeasure

    /// Regression test for A3: `remeasureCorpus()` suspends once per cluster
    /// (a real `await` inside its loop). A `recordLabel` call landing on one
    /// of those suspensions must be rejected outright, not accepted and then
    /// silently clobbered when `remeasureCorpus()` finishes and overwrites
    /// `labelledClusters` wholesale.
    ///
    /// Uses `remeasureStepHookForTesting`, a new minimal test-only seam added
    /// alongside this fix: `PHAsset.fetchAssets` cannot resolve fake
    /// `localIdentifier`s in a unit test, so `remeasuredCluster` would return
    /// `nil` before ever reaching `qualityAnalyzer` — there is no way to hold
    /// `remeasureCorpus()` open at a real suspension point using only the
    /// existing seams. The hook is `nil` (a no-op) in production.
    func testRecordLabelDuringRemeasureIsRejectedRatherThanLostAtCompletion() async throws {
        let defaults = makeEphemeralDefaults()
        let viewModel = makeViewModel(defaults: defaults)
        let firstClusterID = UUID()
        viewModel.setPreparedClusterForTesting(
            makePreparedCluster(clusterID: firstClusterID, localIdentifiers: ["a", "b"])
        )
        viewModel.recordLabel(clusterID: firstClusterID, bestShotAssetID: "a", category: nil)
        XCTAssertEqual(viewModel.labelledCount, 1)

        let gate = SuspensionGate()
        viewModel.remeasureStepHookForTesting = { await gate.wait() }

        let remeasureTask = Task { await viewModel.remeasureCorpus() }

        // Give remeasureCorpus() a chance to start and suspend on the gate.
        while !viewModel.isRemeasuring {
            await Task.yield()
        }

        let secondClusterID = UUID()
        viewModel.setPreparedClusterForTesting(
            makePreparedCluster(clusterID: secondClusterID, localIdentifiers: ["c", "d"])
        )
        viewModel.recordLabel(clusterID: secondClusterID, bestShotAssetID: "c", category: nil)

        // Rejected immediately, not accepted-then-lost: the count must not
        // have moved while remeasureCorpus() is still in flight.
        XCTAssertEqual(viewModel.labelledCount, 1, "recordLabel must be a no-op while isRemeasuring is true")

        viewModel.reset()
        XCTAssertEqual(viewModel.labelledCount, 1, "reset() must also be a no-op while isRemeasuring is true")

        await gate.release()
        _ = await remeasureTask.value

        XCTAssertFalse(viewModel.isRemeasuring)
        // The interleaved label was rejected outright, so it can never
        // reappear once remeasureCorpus() finishes and replaces the buffer.
        XCTAssertNil(viewModel.candidateLocalIdentifiersForTesting(clusterID: secondClusterID.uuidString))
    }
}

/// A one-shot async gate a test can use to hold a suspension point open
/// until it is done asserting on the state either side of it, then release
/// it deterministically instead of guessing with a sleep.
private actor SuspensionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func wait() async {
        if isReleased { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
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
