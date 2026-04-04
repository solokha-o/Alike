import Core
import Foundation

/// JSON-backed active cleanup session repository.
public final class FileCleanupSessionRepository: CleanupSessionRepository, Sendable {
    private let store: CleanupSessionStore

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.store = CleanupSessionStore(
            fileURL: fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        )
    }

    public func loadActiveSession() async throws -> CleanupSession? {
        try await store.load()
    }

    public func saveActiveSession(_ session: CleanupSession) async throws {
        try await store.save(session)
    }

    public func deleteActiveSession() async throws {
        try await store.delete()
    }
}

private extension FileCleanupSessionRepository {
    static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Alike", isDirectory: true)
            .appendingPathComponent("cleanup_session.json", isDirectory: false)
    }
}

actor CleanupSessionStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() throws -> CleanupSession? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let payload = try decoder.decode(CleanupSessionPayload.self, from: data)
            return payload.session
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to load cleanup session: \(error.localizedDescription)"))"
            )
            return nil
        }
    }

    func save(_ session: CleanupSession) throws {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let payload = CleanupSessionPayload(session: session)
        let data = try encoder.encode(payload)
        let temporaryURL = fileURL.appendingPathExtension("tmp")

        try data.write(to: temporaryURL, options: .atomic)

        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }
    }

    func delete() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try fileManager.removeItem(at: fileURL)
    }
}

private struct CleanupSessionPayload: Codable {
    let session: CleanupSession
}
