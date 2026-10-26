import Foundation
import Testing
import Core
@testable import Storage

/// A `final class` suite: each test gets its own `UUID` directory, and `deinit` removes it.
@Suite final class FileCleanupCategorySnapshotRepositoryTests {
    private let directoryURL: URL
    private let fileURL: URL
    private let repository: FileCleanupCategorySnapshotRepository

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        fileURL = directoryURL.appendingPathComponent("cleanup_category_snapshots.json")
        repository = FileCleanupCategorySnapshotRepository(fileURL: fileURL)
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    @Test func testSaveAndLoadSnapshotRoundTrip() async throws {
        let snapshot = CleanupCategorySnapshot(
            kind: .blurredPhotos,
            localIdentifiers: ["one", "two"],
            assetCount: 2,
            estimatedSavingsBytes: 2_048
        )

        try await repository.saveSnapshot(snapshot)

        let loaded = try await repository.loadSnapshot(for: .blurredPhotos)
        #expect(loaded == snapshot)
    }

    @Test func testOverwriteExistingSnapshot() async throws {
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
        #expect(loaded == updated)
    }

    /// Snapshots written before `byteSizeVersion` existed still load, marked as
    /// heuristic so the workspace re-measures them instead of dropping them.
    @Test func testLoadsSnapshotsPersistedBeforeByteSizeVersion() async throws {
        let legacyJSON = """
        {
          "snapshots": [
            {
              "kind": "screenshots",
              "localIdentifiers": ["one", "two"],
              "assetCount": 2,
              "estimatedSavingsBytes": 2048,
              "refreshedAt": 1000
            }
          ]
        }
        """
        try Data(legacyJSON.utf8).write(to: fileURL)

        let loaded = try await repository.loadSnapshot(for: .screenshots)

        #expect(loaded?.localIdentifiers == ["one", "two"])
        #expect(loaded?.estimatedSavingsBytes == 2048)
        #expect(loaded?.byteSizeVersion == nil)
    }

    @Test func testCorruptedJSONReturnsEmptySnapshots() async throws {
        try Data("not-json".utf8).write(to: fileURL)

        let loaded = try await repository.loadAllSnapshots()
        #expect(loaded.isEmpty)
    }

    @Test func testConcurrentSavesAcrossRepositoryInstancesPreserveBothCategories() async throws {
        let firstRepository = repository
        let secondRepository = FileCleanupCategorySnapshotRepository(fileURL: fileURL)
        let screenshotSnapshot = CleanupCategorySnapshot(
            kind: .screenshots,
            localIdentifiers: ["shot"],
            assetCount: 1,
            estimatedSavingsBytes: 100
        )
        let blurSnapshot = CleanupCategorySnapshot(
            kind: .blurredPhotos,
            localIdentifiers: ["blur"],
            assetCount: 1,
            estimatedSavingsBytes: 200
        )

        async let saveScreenshots: Void = firstRepository.saveSnapshot(screenshotSnapshot)
        async let saveBlur: Void = secondRepository.saveSnapshot(blurSnapshot)
        _ = try await (saveScreenshots, saveBlur)

        let loaded = try await firstRepository.loadAllSnapshots()
        #expect(loaded[.screenshots] == screenshotSnapshot)
        #expect(loaded[.blurredPhotos] == blurSnapshot)
    }

    @Test func testReplaceAllSnapshotsRemovesStaleCategoriesInOneOperation() async throws {
        let staleSnapshot = makeSnapshot(kind: .screenshots, generation: "stale")
        let replacement = makeSnapshot(kind: .blurredPhotos, generation: "replacement")
        try await repository.saveSnapshot(staleSnapshot)

        try await repository.replaceAllSnapshots([replacement])

        let loaded = try await repository.loadAllSnapshots()
        #expect(loaded == [.blurredPhotos: replacement])
    }

    @Test func testConcurrentReadersOnlyObserveCompleteReplacements() async throws {
        let repository = self.repository
        let firstGeneration = CleanupCategoryKind.allCases.map {
            makeSnapshot(kind: $0, generation: "first")
        }
        let secondGeneration = CleanupCategoryKind.allCases.map {
            makeSnapshot(kind: $0, generation: "second")
        }
        try await repository.replaceAllSnapshots(firstGeneration)

        let observations = try await withThrowingTaskGroup(
            of: [CleanupCategoryKind: CleanupCategorySnapshot].self
        ) { group in
            for iteration in 0..<40 {
                group.addTask {
                    let replacement = iteration.isMultiple(of: 2) ? firstGeneration : secondGeneration
                    try await repository.replaceAllSnapshots(replacement)
                    return try await repository.loadAllSnapshots()
                }
            }

            var results: [[CleanupCategoryKind: CleanupCategorySnapshot]] = []
            for try await observation in group {
                results.append(observation)
            }
            return results
        }

        for observation in observations {
            #expect(observation.count == CleanupCategoryKind.allCases.count)
            let generations = Set(observation.values.flatMap(\.localIdentifiers))
            #expect(generations == ["first"] || generations == ["second"])
        }
    }

    @Test func testFailedReplacementPreservesPreviouslyStoredSnapshots() async throws {
        let original = CleanupCategoryKind.allCases.map {
            makeSnapshot(kind: $0, generation: "original")
        }
        try await repository.replaceAllSnapshots(original)
        let temporaryFileURL = fileURL.appendingPathExtension("tmp")
        try FileManager.default.createDirectory(at: temporaryFileURL, withIntermediateDirectories: true)

        do {
            try await repository.replaceAllSnapshots([
                makeSnapshot(kind: .screenshots, generation: "replacement")
            ])
            Issue.record("Expected replacement to fail")
        } catch {
            // The write failure is expected; verify the committed file was not changed.
        }

        let loaded = try await repository.loadAllSnapshots()
        #expect(loaded == Dictionary(uniqueKeysWithValues: original.map { ($0.kind, $0) }))
    }
}

private extension FileCleanupCategorySnapshotRepositoryTests {
    func makeSnapshot(
        kind: CleanupCategoryKind,
        generation: String
    ) -> CleanupCategorySnapshot {
        CleanupCategorySnapshot(
            kind: kind,
            localIdentifiers: [generation],
            assetCount: 1,
            estimatedSavingsBytes: kind == .screenshots ? 100 : 200
        )
    }
}
