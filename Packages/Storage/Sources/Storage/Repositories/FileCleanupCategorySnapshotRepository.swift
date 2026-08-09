import Core
import Foundation

/// JSON-backed repository for persisted cleanup category snapshots.
public final class FileCleanupCategorySnapshotRepository: CleanupCategorySnapshotRepository, Sendable {
    private let store: CleanupCategorySnapshotStore

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.store = CleanupFileStoreRegistry.shared.categorySnapshotStore(
            for: fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        )
    }

    public func loadSnapshot(for kind: CleanupCategoryKind) async throws -> CleanupCategorySnapshot? {
        try await store.loadAllSnapshots()[kind]
    }

    public func loadAllSnapshots() async throws -> [CleanupCategoryKind: CleanupCategorySnapshot] {
        try await store.loadAllSnapshots()
    }

    public func saveSnapshot(_ snapshot: CleanupCategorySnapshot) async throws {
        try await store.saveSnapshot(snapshot)
    }

    public func replaceAllSnapshots(_ snapshots: [CleanupCategorySnapshot]) async throws {
        try await store.replaceAllSnapshots(snapshots)
    }

    public func deleteAllSnapshots() async throws {
        try await store.replaceAllSnapshots([])
    }
}

private extension FileCleanupCategorySnapshotRepository {
    static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Alike", isDirectory: true)
            .appendingPathComponent("cleanup_category_snapshots.json", isDirectory: false)
    }
}

actor CleanupCategorySnapshotStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadAllSnapshots() throws -> [CleanupCategoryKind: CleanupCategorySnapshot] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let payload = try decoder.decode(CleanupCategorySnapshotPayload.self, from: data)
            return Dictionary(uniqueKeysWithValues: payload.snapshots.map { ($0.kind, $0) })
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to load cleanup category snapshots: \(error.localizedDescription)"))"
            )
            return [:]
        }
    }

    func saveAllSnapshots(_ snapshots: [CleanupCategoryKind: CleanupCategorySnapshot]) throws {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let payload = CleanupCategorySnapshotPayload(
            snapshots: snapshots.values.sorted { $0.kind.rawValue < $1.kind.rawValue }
        )
        let data = try encoder.encode(payload)
        let temporaryURL = fileURL.appendingPathExtension("tmp")

        try data.write(to: temporaryURL, options: .atomic)

        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }
    }

    func saveSnapshot(_ snapshot: CleanupCategorySnapshot) throws {
        var snapshots = try loadAllSnapshots()
        snapshots[snapshot.kind] = snapshot
        try saveAllSnapshots(snapshots)
    }

    func replaceAllSnapshots(_ snapshots: [CleanupCategorySnapshot]) throws {
        let snapshotsByKind = snapshots.reduce(into: [:]) { result, snapshot in
            result[snapshot.kind] = snapshot
        }
        try saveAllSnapshots(snapshotsByKind)
    }
}

private struct CleanupCategorySnapshotPayload: Codable {
    let snapshots: [CleanupCategorySnapshot]
}
