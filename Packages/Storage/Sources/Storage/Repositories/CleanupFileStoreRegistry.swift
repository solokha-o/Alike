import Foundation

/// Keeps file-backed cleanup repositories that target the same URL on one actor.
final class CleanupFileStoreRegistry: @unchecked Sendable {
    static let shared = CleanupFileStoreRegistry()

    private let lock = NSLock()
    private var historyStores: [URL: CleanupHistoryStore] = [:]
    private var categorySnapshotStores: [URL: CleanupCategorySnapshotStore] = [:]

    private init() {}

    func historyStore(for fileURL: URL) -> CleanupHistoryStore {
        let key = canonicalURL(fileURL)
        lock.lock()
        defer { lock.unlock() }

        if let store = historyStores[key] {
            return store
        }
        let store = CleanupHistoryStore(fileURL: key)
        historyStores[key] = store
        return store
    }

    func categorySnapshotStore(for fileURL: URL) -> CleanupCategorySnapshotStore {
        let key = canonicalURL(fileURL)
        lock.lock()
        defer { lock.unlock() }

        if let store = categorySnapshotStores[key] {
            return store
        }
        let store = CleanupCategorySnapshotStore(fileURL: key)
        categorySnapshotStores[key] = store
        return store
    }

    private func canonicalURL(_ fileURL: URL) -> URL {
        fileURL.standardizedFileURL
    }
}
