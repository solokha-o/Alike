import Core
import Foundation

/// JSON-backed cleanup history repository.
public final class FileCleanupHistoryRepository: CleanupHistoryRepository, Sendable {
    private let store: CleanupHistoryStore

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.store = CleanupHistoryStore(
            fileURL: fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        )
    }

    public func loadEntries() async throws -> [CleanupCompletionRecord] {
        try await store.loadEntries()
    }

    public func append(_ entry: CleanupCompletionRecord) async throws {
        var entries = try await store.loadEntries()
        entries.append(entry)
        try await store.saveEntries(entries)
    }
}

private extension FileCleanupHistoryRepository {
    static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Alike", isDirectory: true)
            .appendingPathComponent("cleanup_history.json", isDirectory: false)
    }
}

actor CleanupHistoryStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadEntries() throws -> [CleanupCompletionRecord] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let payload = try decoder.decode(CleanupHistoryPayload.self, from: data)
            return payload.entries.sorted { lhs, rhs in
                lhs.completedAt < rhs.completedAt
            }
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to load cleanup history: \(error.localizedDescription)"))"
            )
            return []
        }
    }

    func saveEntries(_ entries: [CleanupCompletionRecord]) throws {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let payload = CleanupHistoryPayload(entries: entries)
        let data = try encoder.encode(payload)
        let temporaryURL = fileURL.appendingPathExtension("tmp")

        try data.write(to: temporaryURL, options: .atomic)

        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }
    }
}

private struct CleanupHistoryPayload: Codable {
    let entries: [CleanupCompletionRecord]
}
