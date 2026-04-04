import XCTest
import Core
@testable import Storage

final class FileCleanupSessionRepositoryTests: XCTestCase {
    private var directoryURL: URL!
    private var fileURL: URL!
    private var repository: FileCleanupSessionRepository!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        fileURL = directoryURL.appendingPathComponent("cleanup_session.json")
        repository = FileCleanupSessionRepository(fileURL: fileURL)
    }

    override func tearDownWithError() throws {
        repository = nil
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func testSaveAndLoadActiveSessionRoundTrip() async throws {
        let session = CleanupSession(
            totalClusters: 10,
            reviewedClusters: 4,
            estimatedSavingsBytes: 3_000
        )

        try await repository.saveActiveSession(session)
        let loaded = try await repository.loadActiveSession()

        XCTAssertEqual(loaded, session)
    }

    func testSavingSecondSessionOverwritesFirst() async throws {
        let first = CleanupSession(
            totalClusters: 5,
            reviewedClusters: 1,
            estimatedSavingsBytes: 100
        )
        let second = CleanupSession(
            totalClusters: 12,
            reviewedClusters: 7,
            estimatedSavingsBytes: 6_000
        )

        try await repository.saveActiveSession(first)
        try await repository.saveActiveSession(second)

        let loaded = try await repository.loadActiveSession()
        XCTAssertEqual(loaded, second)
    }

    func testDeleteActiveSessionRemovesSavedData() async throws {
        let session = CleanupSession(
            totalClusters: 3,
            reviewedClusters: 2,
            estimatedSavingsBytes: 500
        )
        try await repository.saveActiveSession(session)

        try await repository.deleteActiveSession()
        let loaded = try await repository.loadActiveSession()

        XCTAssertNil(loaded)
    }

    func testCorruptedJSONReturnsNilSession() async throws {
        try Data("not-json".utf8).write(to: fileURL)

        let loaded = try await repository.loadActiveSession()
        XCTAssertNil(loaded)
    }
}
