import XCTest
import Core
@testable import Storage

final class FileCleanupHistoryRepositoryTests: XCTestCase {
    private var directoryURL: URL!
    private var fileURL: URL!
    private var repository: FileCleanupHistoryRepository!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        fileURL = directoryURL.appendingPathComponent("cleanup_history.json")
        repository = FileCleanupHistoryRepository(fileURL: fileURL)
    }

    override func tearDownWithError() throws {
        repository = nil
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func testAppendAndLoadEntriesRoundTrip() async throws {
        let entry = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 3,
            estimatedSavingsBytes: 4_096
        )

        try await repository.append(entry)

        let loaded = try await repository.loadEntries()
        XCTAssertEqual(loaded, [entry])
    }

    func testAppendPreservesMultipleEntries() async throws {
        let first = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 1,
            estimatedSavingsBytes: 1_024,
            completedAt: Date(timeIntervalSince1970: 10)
        )
        let second = CleanupCompletionRecord(
            sourceClusterID: UUID(),
            deletedCount: 2,
            estimatedSavingsBytes: 2_048,
            completedAt: Date(timeIntervalSince1970: 20)
        )

        try await repository.append(first)
        try await repository.append(second)

        let loaded = try await repository.loadEntries()
        XCTAssertEqual(loaded, [first, second])
    }

    func testCorruptedJSONReturnsEmptyEntries() async throws {
        try Data("not-json".utf8).write(to: fileURL)

        let loaded = try await repository.loadEntries()
        XCTAssertTrue(loaded.isEmpty)
    }
}
