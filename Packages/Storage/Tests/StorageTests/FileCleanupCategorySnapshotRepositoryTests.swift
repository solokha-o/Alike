import XCTest
import Core
@testable import Storage

final class FileCleanupCategorySnapshotRepositoryTests: XCTestCase {
    private var directoryURL: URL!
    private var fileURL: URL!
    private var repository: FileCleanupCategorySnapshotRepository!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        fileURL = directoryURL.appendingPathComponent("cleanup_category_snapshots.json")
        repository = FileCleanupCategorySnapshotRepository(fileURL: fileURL)
    }

    override func tearDownWithError() throws {
        repository = nil
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func testSaveAndLoadSnapshotRoundTrip() async throws {
        let snapshot = CleanupCategorySnapshot(
            kind: .blurredPhotos,
            localIdentifiers: ["one", "two"],
            assetCount: 2,
            estimatedSavingsBytes: 2_048
        )

        try await repository.saveSnapshot(snapshot)

        let loaded = try await repository.loadSnapshot(for: .blurredPhotos)
        XCTAssertEqual(loaded, snapshot)
    }

    func testOverwriteExistingSnapshot() async throws {
        let initial = CleanupCategorySnapshot(
            kind: .screenshots,
            localIdentifiers: ["old"],
            assetCount: 1,
            estimatedSavingsBytes: 100
        )
        let updated = CleanupCategorySnapshot(
            kind: .screenshots,
            localIdentifiers: ["new", "newer"],
            assetCount: 2,
            estimatedSavingsBytes: 300
        )

        try await repository.saveSnapshot(initial)
        try await repository.saveSnapshot(updated)

        let loaded = try await repository.loadSnapshot(for: .screenshots)
        XCTAssertEqual(loaded, updated)
    }

    func testCorruptedJSONReturnsEmptySnapshots() async throws {
        try Data("not-json".utf8).write(to: fileURL)

        let loaded = try await repository.loadAllSnapshots()
        XCTAssertTrue(loaded.isEmpty)
    }
}
