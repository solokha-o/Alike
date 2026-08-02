import Foundation
import Core

public protocol LocalAppDataDeleting: Sendable {
    func deleteAllData() async throws
}

/// Deletes user-facing, app-generated data while retaining StoreKit and
/// installation-local monetization state.
public actor LocalAppDataDeletionService: LocalAppDataDeleting {
    private let deletePersistentData: @Sendable () async throws -> Void
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let applicationSupportDirectoryURL: URL

    public init(
        persistence: PersistenceController = .shared,
        fileManager: FileManager = .default,
        userDefaultsSuiteName: String? = nil,
        applicationSupportDirectoryURL: URL? = nil
    ) {
        self.deletePersistentData = {
            try await persistence.deleteAllData()
        }
        self.fileManager = fileManager
        self.userDefaults = userDefaultsSuiteName
            .flatMap(UserDefaults.init(suiteName:))
            ?? .standard
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
    }

    init(
        deletePersistentData: @escaping @Sendable () async throws -> Void,
        fileManager: FileManager,
        userDefaultsSuiteName: String,
        applicationSupportDirectoryURL: URL
    ) {
        self.deletePersistentData = deletePersistentData
        self.fileManager = fileManager
        self.userDefaults = UserDefaults(suiteName: userDefaultsSuiteName) ?? .standard
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
    }

    public func deleteAllData() async throws {
        try await deletePersistentData()

        let alikeDirectoryURL = applicationSupportDirectoryURL
            .appendingPathComponent("Alike", isDirectory: true)
        if fileManager.fileExists(atPath: alikeDirectoryURL.path) {
            try fileManager.removeItem(at: alikeDirectoryURL)
        }

        for key in AppPreferenceKey.resettable {
            userDefaults.removeObject(forKey: key)
        }
    }
}
