import CoreData
import Core
import Foundation
import Testing
@testable import Storage

/// A `final class` suite: each test gets its own `UUID` directory and `UserDefaults` suite, and `deinit` removes both.
/// `@MainActor`: the tests seed and read `viewContext`, a main-queue context.
@MainActor
@Suite final class LocalAppDataDeletionServiceTests {
    private let directoryURL: URL
    private let defaults: UserDefaults
    private let suiteName: String

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        suiteName = "LocalAppDataDeletionServiceTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        // `deinit` is nonisolated and `UserDefaults` is not `Sendable`, so it
        // opens the suite by name instead of using `defaults`.
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directoryURL)
    }

    @Test func testDeleteAllDataRemovesAppDataAndPreservesMonetizationState() async throws {
        let persistence = PersistenceController.preview()
        try seedPersistence(persistence)
        let alikeDirectory = directoryURL.appendingPathComponent("Alike", isDirectory: true)
        try FileManager.default.createDirectory(at: alikeDirectory, withIntermediateDirectories: true)
        try Data("history".utf8).write(to: alikeDirectory.appendingPathComponent("cleanup_history.json"))
        let unrelatedFile = directoryURL.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: unrelatedFile)

        for key in AppPreferenceKey.resettable {
            defaults.set("remove", forKey: key)
        }
        defaults.set(Data([1]), forKey: AppPreferenceKey.Premium.monthlyScanUsage)
        defaults.set(true, forKey: AppPreferenceKey.Premium.postFirstUsefulScanPrompt)
        defaults.set(Data([2]), forKey: AppPreferenceKey.Premium.subscriptionEntitlement)

        let service = LocalAppDataDeletionService(
            persistence: persistence,
            userDefaultsSuiteName: suiteName,
            applicationSupportDirectoryURL: directoryURL
        )

        try await service.deleteAllData()
        try await service.deleteAllData()

        #expect(!(FileManager.default.fileExists(atPath: alikeDirectory.path)))
        #expect(FileManager.default.fileExists(atPath: unrelatedFile.path))
        for key in AppPreferenceKey.resettable {
            #expect(defaults.object(forKey: key) == nil, "Expected \(key) to be removed")
        }
        #expect(defaults.data(forKey: AppPreferenceKey.Premium.monthlyScanUsage) != nil)
        #expect(defaults.bool(forKey: AppPreferenceKey.Premium.postFirstUsefulScanPrompt))
        #expect(defaults.data(forKey: AppPreferenceKey.Premium.subscriptionEntitlement) != nil)
        try assertPersistenceIsEmpty(persistence)
    }

    @Test func testPersistentDeletionFailurePropagatesBeforeOtherDataIsRemoved() async throws {
        let alikeDirectory = directoryURL.appendingPathComponent("Alike", isDirectory: true)
        try FileManager.default.createDirectory(at: alikeDirectory, withIntermediateDirectories: true)
        defaults.set(3, forKey: AppPreferenceKey.PhotoGrid.compactColumns)
        let service = LocalAppDataDeletionService(
            deletePersistentData: { throw ExpectedError.failure },
            fileManager: .default,
            userDefaultsSuiteName: suiteName,
            applicationSupportDirectoryURL: directoryURL
        )

        do {
            try await service.deleteAllData()
            Issue.record("Expected deletion to fail")
        } catch {
            #expect(error as? ExpectedError == .failure)
        }

        #expect(FileManager.default.fileExists(atPath: alikeDirectory.path))
        #expect(defaults.integer(forKey: AppPreferenceKey.PhotoGrid.compactColumns) == 3)
    }

    private func seedPersistence(_ persistence: PersistenceController) throws {
        let context = persistence.viewContext
        let cluster = ClusterEntity(context: context)
        cluster.id = UUID()
        cluster.createdAt = Date()
        cluster.averageSimilarity = 0.9
        let photo = PhotoEntity(context: context)
        photo.localIdentifier = "photo"
        photo.cluster = cluster
        let metadata = ScanMetadataEntity(context: context)
        metadata.lastScanDate = Date()
        try context.save()
    }

    private func assertPersistenceIsEmpty(_ persistence: PersistenceController) throws {
        let context = persistence.viewContext
        #expect(try context.count(for: ClusterEntity.fetchRequest()) == 0)
        #expect(try context.count(for: PhotoEntity.fetchRequest()) == 0)
        #expect(try context.count(for: ScanMetadataEntity.fetchRequest()) == 0)
    }
}

private enum ExpectedError: Error, Equatable {
    case failure
}
