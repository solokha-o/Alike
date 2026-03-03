import Core
import Foundation

/// JSON-backed cleanup review state repository.
public final class FileClusterReviewStateRepository: ClusterReviewStateRepository, Sendable {
    private let store: ClusterReviewStateStore

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.store = ClusterReviewStateStore(
            fileURL: fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        )
    }

    public func loadReviewState(clusterID: UUID) async throws -> ClusterReviewState? {
        try await store.loadAllStates()[clusterID]
    }

    public func loadAllReviewStates() async throws -> [UUID: ClusterReviewState] {
        try await store.loadAllStates()
    }

    public func saveReviewState(_ state: ClusterReviewState) async throws {
        var states = try await store.loadAllStates()
        states[state.clusterID] = state
        try await store.saveAllStates(states)
    }

    public func deleteReviewState(clusterID: UUID) async throws {
        var states = try await store.loadAllStates()
        states.removeValue(forKey: clusterID)
        try await store.saveAllStates(states)
    }

    public func deleteAllReviewStates() async throws {
        try await store.saveAllStates([:])
    }
}

private extension FileClusterReviewStateRepository {
    static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Alike", isDirectory: true)
            .appendingPathComponent("cluster_review_states.json", isDirectory: false)
    }
}

actor ClusterReviewStateStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadAllStates() throws -> [UUID: ClusterReviewState] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let payload = try decoder.decode(ReviewStatePayload.self, from: data)
            return Dictionary(uniqueKeysWithValues: payload.states.map { ($0.clusterID, $0) })
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to load review states: \(error.localizedDescription)"))"
            )
            return [:]
        }
    }

    func saveAllStates(_ states: [UUID: ClusterReviewState]) throws {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let payload = ReviewStatePayload(states: states.values.sorted { lhs, rhs in
            lhs.clusterID.uuidString < rhs.clusterID.uuidString
        })
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

private struct ReviewStatePayload: Codable {
    let states: [ClusterReviewState]
}
