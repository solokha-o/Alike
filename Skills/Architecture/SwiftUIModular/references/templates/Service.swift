// Template: a service protocol, its implementation, and its test double.
// They are 4 files in the repository. Each `// File:` line starts one file.
// Based on:
// - Protocol: `CleanupHistoryRepository` in
//   Packages/Core/Sources/Core/Protocols/Repositories.swift.
// - Model: Packages/Core/Sources/Core/Models/CleanupCompletionRecord.swift.
// - Implementation: Packages/Storage/Sources/Storage/Repositories/
//   UserDefaultsCleanupReminderPreferenceRepository.swift (actor, injected
//   `UserDefaults` and key) and `CleanupHistoryStore` in
//   FileCleanupHistoryRepository.swift (decode, log the failure, rethrow).
// - Mock: Packages/Core/Sources/Core/Mocks/MockCleanupHistoryRepository.swift.
// Do not copy `CleanupFileStoreRegistry.shared` from the implementation: no new
// singleton (written rule 6).
// A new persisted key follows Skills/Storage/persisted-data-evolution.

// MARK: - File: Packages/Core/Sources/Core/Models/FeatureNameEntry.swift

import Foundation

/// One FeatureName entry that the user saved.
public struct FeatureNameEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String

    public init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}

// MARK: - File: Packages/Core/Sources/Core/Protocols/Repositories.swift (append)

/// Repository for the saved FeatureName entries.
public protocol FeatureNameRepository: Sendable {
    /// Load all saved entries.
    func loadEntries() async throws -> [FeatureNameEntry]

    /// Save one entry after the existing entries.
    func append(_ entry: FeatureNameEntry) async throws
}

// MARK: - File: Packages/Storage/Sources/Storage/Repositories/UserDefaultsFeatureNameRepository.swift

// Imports in this file: Core, Foundation.

/// UserDefaults-backed FeatureName repository.
public actor UserDefaultsFeatureNameRepository: FeatureNameRepository {
    private let userDefaults: UserDefaults
    private let entriesKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(userDefaults: UserDefaults, entriesKey: String) {
        self.userDefaults = userDefaults
        self.entriesKey = entriesKey
    }

    public func loadEntries() async throws -> [FeatureNameEntry] {
        guard let data = userDefaults.data(forKey: entriesKey) else {
            return []
        }

        do {
            return try decoder.decode([FeatureNameEntry].self, from: data)
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to load FeatureName entries: \(error.localizedDescription)"))"
            )
            throw error
        }
    }

    public func append(_ entry: FeatureNameEntry) async throws {
        var entries = try await loadEntries()
        entries.append(entry)
        try userDefaults.set(encoder.encode(entries), forKey: entriesKey)
    }
}

// MARK: - File: Packages/Core/Sources/Core/Mocks/MockFeatureNameRepository.swift

// Imports in this file: Foundation.

#if DEBUG

public actor MockFeatureNameRepository: FeatureNameRepository {
    public var entries: [FeatureNameEntry]
    public var loadEntriesError: Error?

    public var didCallLoadEntries = false
    public var didCallAppend = false

    public init(entries: [FeatureNameEntry] = []) {
        self.entries = entries
    }

    public func setLoadEntriesError(_ error: Error?) {
        loadEntriesError = error
    }

    public func loadEntries() async throws -> [FeatureNameEntry] {
        didCallLoadEntries = true
        if let loadEntriesError {
            throw loadEntriesError
        }
        return entries
    }

    public func append(_ entry: FeatureNameEntry) async throws {
        didCallAppend = true
        entries.append(entry)
    }
}

#endif
