import Foundation
import Testing
import Core
@testable import Storage

@Suite struct FileCleanupSessionRepositoryTests {
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

    @Test func testSaveAndLoadActiveSessionRoundTrip() async throws {
        let session = CleanupSession(
            totalClusters: 10,
            reviewedClusters: 4,
            estimatedSavingsBytes: 3_000
        )

        try await repository.saveActiveSession(session)
        let loaded = try await repository.loadActiveSession()

        #expect(loaded == session)
    }

    @Test func testSavingSecondSessionOverwritesFirst() async throws {
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
        #expect(loaded == second)
    }

    @Test func testDeleteActiveSessionRemovesSavedData() async throws {
        let session = CleanupSession(
            totalClusters: 3,
            reviewedClusters: 2,
            estimatedSavingsBytes: 500
        )
        try await repository.saveActiveSession(session)

        try await repository.deleteActiveSession()
        let loaded = try await repository.loadActiveSession()

        #expect(loaded == nil)
    }

    @Test func testCorruptedJSONReturnsNilSession() async throws {
        try Data("not-json".utf8).write(to: fileURL)

        let loaded = try await repository.loadActiveSession()
        #expect(loaded == nil)
    }
}
