import XCTest
import Core
@testable import Storage

final class FileClusterReviewStateRepositoryTests: XCTestCase {
    private var directoryURL: URL!
    private var fileURL: URL!
    private var repository: FileClusterReviewStateRepository!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        fileURL = directoryURL.appendingPathComponent("cluster_review_states.json")
        repository = FileClusterReviewStateRepository(fileURL: fileURL)
    }

    override func tearDownWithError() throws {
        repository = nil
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func testSaveAndLoadReviewStateRoundTrip() async throws {
        let clusterID = UUID()
        let state = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: ["candidate-1", "candidate-2"],
            mode: .keepBestOnly,
            status: .reviewed,
            estimatedSavingsBytes: 2_048
        )

        try await repository.saveReviewState(state)

        let loaded = try await repository.loadReviewState(clusterID: clusterID)
        XCTAssertEqual(loaded, state)
    }

    func testSaveAndLoadNeedsReReviewStateRoundTrip() async throws {
        let clusterID = UUID()
        let state = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: [],
            mode: .selection,
            status: .needsReReview,
            estimatedSavingsBytes: 0,
            resurfacingState: .new
        )

        try await repository.saveReviewState(state)

        let loaded = try await repository.loadReviewState(clusterID: clusterID)
        XCTAssertEqual(loaded, state)
    }

    func testLoadAllReturnsMultipleStates() async throws {
        let first = ClusterReviewState(
            clusterID: UUID(),
            bestShotLocalIdentifier: "a",
            selectedLocalIdentifiers: [],
            mode: .selection,
            status: .notReviewed,
            estimatedSavingsBytes: 0
        )
        let second = ClusterReviewState(
            clusterID: UUID(),
            bestShotLocalIdentifier: "b",
            selectedLocalIdentifiers: ["c"],
            mode: .keepBestOnly,
            status: .inReview,
            estimatedSavingsBytes: 512
        )

        try await repository.saveReviewState(first)
        try await repository.saveReviewState(second)

        let loaded = try await repository.loadAllReviewStates()
        XCTAssertEqual(loaded[first.clusterID], first)
        XCTAssertEqual(loaded[second.clusterID], second)
    }

    func testSavingSameClusterOverwritesState() async throws {
        let clusterID = UUID()
        let initial = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: [],
            mode: .selection,
            status: .notReviewed,
            estimatedSavingsBytes: 0
        )
        let updated = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "best",
            selectedLocalIdentifiers: ["candidate"],
            mode: .keepBestOnly,
            status: .inReview,
            estimatedSavingsBytes: 1_024
        )

        try await repository.saveReviewState(initial)
        try await repository.saveReviewState(updated)

        let loaded = try await repository.loadReviewState(clusterID: clusterID)
        XCTAssertEqual(loaded, updated)
    }

    func testDeleteReviewStateKeepsOtherStates() async throws {
        let first = ClusterReviewState(
            clusterID: UUID(),
            bestShotLocalIdentifier: "a",
            selectedLocalIdentifiers: [],
            mode: .selection,
            status: .notReviewed,
            estimatedSavingsBytes: 0
        )
        let second = ClusterReviewState(
            clusterID: UUID(),
            bestShotLocalIdentifier: "b",
            selectedLocalIdentifiers: ["c"],
            mode: .keepBestOnly,
            status: .reviewed,
            estimatedSavingsBytes: 256
        )

        try await repository.saveReviewState(first)
        try await repository.saveReviewState(second)
        try await repository.deleteReviewState(clusterID: first.clusterID)

        let loaded = try await repository.loadAllReviewStates()
        XCTAssertNil(loaded[first.clusterID])
        XCTAssertEqual(loaded[second.clusterID], second)
    }

    /// States written before the best-shot override flag existed must still
    /// decode: a decoding failure here drops every cluster's review progress.
    func testLoadsStatesPersistedBeforeBestShotOverrideFlag() async throws {
        let clusterID = UUID()
        let legacyJSON = """
        {
          "states": [
            {
              "clusterID": "\(clusterID.uuidString)",
              "bestShotLocalIdentifier": "best",
              "selectedLocalIdentifiers": ["candidate"],
              "mode": "selection",
              "status": "reviewed",
              "estimatedSavingsBytes": 2048,
              "updatedAt": 1000
            }
          ]
        }
        """
        try Data(legacyJSON.utf8).write(to: fileURL)

        let loaded = try await repository.loadReviewState(clusterID: clusterID)

        XCTAssertEqual(loaded?.bestShotLocalIdentifier, "best")
        XCTAssertEqual(loaded?.selectedLocalIdentifiers, ["candidate"])
        XCTAssertEqual(loaded?.status, .reviewed)
        XCTAssertEqual(loaded?.isBestShotUserSelected, false)
    }

    /// Reviews finished before the explicit confirmation existed were stored as
    /// `.reviewed`, so they must come back confirmed instead of reopening.
    func testLoadsReviewedStatePersistedBeforeConfirmationFlag() async throws {
        let clusterID = UUID()
        let legacyJSON = """
        {
          "states": [
            {
              "clusterID": "\(clusterID.uuidString)",
              "bestShotLocalIdentifier": "best",
              "selectedLocalIdentifiers": ["candidate"],
              "mode": "selection",
              "status": "reviewed",
              "estimatedSavingsBytes": 2048,
              "updatedAt": 1000
            }
          ]
        }
        """
        try Data(legacyJSON.utf8).write(to: fileURL)

        let loaded = try await repository.loadReviewState(clusterID: clusterID)

        XCTAssertEqual(loaded?.isReviewConfirmed, true)
    }

    func testLoadsUnfinishedStatePersistedBeforeConfirmationFlag() async throws {
        let clusterID = UUID()
        let legacyJSON = """
        {
          "states": [
            {
              "clusterID": "\(clusterID.uuidString)",
              "bestShotLocalIdentifier": "best",
              "selectedLocalIdentifiers": ["candidate"],
              "mode": "selection",
              "status": "inReview",
              "estimatedSavingsBytes": 2048,
              "updatedAt": 1000
            }
          ]
        }
        """
        try Data(legacyJSON.utf8).write(to: fileURL)

        let loaded = try await repository.loadReviewState(clusterID: clusterID)

        XCTAssertEqual(loaded?.isReviewConfirmed, false)
    }

    func testSaveAndLoadUserSelectedBestShotRoundTrip() async throws {
        let clusterID = UUID()
        let state = ClusterReviewState(
            clusterID: clusterID,
            bestShotLocalIdentifier: "chosen",
            isBestShotUserSelected: true,
            selectedLocalIdentifiers: ["other"],
            mode: .selection,
            status: .reviewed,
            estimatedSavingsBytes: 128
        )

        try await repository.saveReviewState(state)

        let loaded = try await repository.loadReviewState(clusterID: clusterID)
        XCTAssertEqual(loaded, state)
        XCTAssertEqual(loaded?.isBestShotUserSelected, true)
    }

    func testCorruptedJSONReturnsEmptyStateMap() async throws {
        try Data("not-json".utf8).write(to: fileURL)

        let loaded = try await repository.loadAllReviewStates()
        XCTAssertTrue(loaded.isEmpty)
    }
}
