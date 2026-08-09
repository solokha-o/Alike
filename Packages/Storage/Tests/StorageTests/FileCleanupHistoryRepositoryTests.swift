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

    func testCorruptedJSONThrowsAndAppendDoesNotOverwriteFile() async throws {
        let corruptedData = Data("not-json".utf8)
        try corruptedData.write(to: fileURL)

        do {
            _ = try await repository.loadEntries()
            XCTFail("Expected corrupted history to throw")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }

        do {
            try await repository.append(
                CleanupCompletionRecord(
                    sourceClusterID: UUID(),
                    deletedCount: 1,
                    estimatedSavingsBytes: 100
                )
            )
            XCTFail("Expected append to preserve and reject corrupted history")
        } catch {
            XCTAssertEqual(try Data(contentsOf: fileURL), corruptedData)
        }
    }

    func testConcurrentAppendsAcrossRepositoryInstancesPreserveEveryEntry() async throws {
        let firstRepository = try XCTUnwrap(repository)
        let secondRepository = FileCleanupHistoryRepository(fileURL: fileURL)
        let records = (0..<40).map { index in
            CleanupCompletionRecord(
                sourceClusterID: UUID(),
                deletedCount: index + 1,
                estimatedSavingsBytes: Int64(index + 1),
                completedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, record) in records.enumerated() {
                let target = index.isMultiple(of: 2) ? firstRepository : secondRepository
                group.addTask {
                    try await target.append(record)
                }
            }
            try await group.waitForAll()
        }

        let loaded = try await firstRepository.loadEntries()
        XCTAssertEqual(Set(loaded.map(\.id)), Set(records.map(\.id)))
    }
}
