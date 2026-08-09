import Foundation

#if DEBUG

public actor MockCleanupHistoryRepository: CleanupHistoryRepository {
    public var entries: [CleanupCompletionRecord]
    public var loadEntriesError: Error?
    public var appendError: Error?

    public var didCallLoadEntries = false
    public var didCallAppend = false

    public init(entries: [CleanupCompletionRecord] = []) {
        self.entries = entries
    }

    public func setEntries(_ entries: [CleanupCompletionRecord]) {
        self.entries = entries
    }

    public func setLoadEntriesError(_ error: Error?) {
        loadEntriesError = error
    }

    public func loadEntries() async throws -> [CleanupCompletionRecord] {
        didCallLoadEntries = true
        if let loadEntriesError {
            throw loadEntriesError
        }
        return entries
    }

    public func append(_ entry: CleanupCompletionRecord) async throws {
        didCallAppend = true
        if let appendError {
            throw appendError
        }
        entries.append(entry)
    }
}

#endif
