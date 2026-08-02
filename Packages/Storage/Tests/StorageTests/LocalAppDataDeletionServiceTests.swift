import CoreData
import Core
import Foundation
import XCTest
@testable import Storage

final class LocalAppDataDeletionServiceTests: XCTestCase {
    private var directoryURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        suiteName = "LocalAppDataDeletionServiceTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        directoryURL = nil
    }

    func testDeleteAllDataRemovesAppDataAndPreservesMonetizationState() async throws {
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

        XCTAssertFalse(FileManager.default.fileExists(atPath: alikeDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedFile.path))
        for key in AppPreferenceKey.resettable {
            XCTAssertNil(defaults.object(forKey: key), "Expected \(key) to be removed")
        }
        XCTAssertNotNil(defaults.data(forKey: AppPreferenceKey.Premium.monthlyScanUsage))
        XCTAssertTrue(defaults.bool(forKey: AppPreferenceKey.Premium.postFirstUsefulScanPrompt))
        XCTAssertNotNil(defaults.data(forKey: AppPreferenceKey.Premium.subscriptionEntitlement))
        try assertPersistenceIsEmpty(persistence)
    }

    func testPersistentDeletionFailurePropagatesBeforeOtherDataIsRemoved() async throws {
        let alikeDirectory = directoryURL.appendingPathComponent("Alike", isDirectory: true)
        try FileManager.default.createDirectory(at: alikeDirectory, withIntermediateDirectories: true)
        defaults.set(3, forKey: AppPreferenceKey.gridColumns)
        let service = LocalAppDataDeletionService(
            deletePersistentData: { throw ExpectedError.failure },
            fileManager: .default,
            userDefaultsSuiteName: suiteName,
            applicationSupportDirectoryURL: directoryURL
        )

        do {
            try await service.deleteAllData()
            XCTFail("Expected deletion to fail")
        } catch {
            XCTAssertEqual(error as? ExpectedError, .failure)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: alikeDirectory.path))
        XCTAssertEqual(defaults.integer(forKey: AppPreferenceKey.gridColumns), 3)
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
        XCTAssertEqual(try context.count(for: ClusterEntity.fetchRequest()), 0)
        XCTAssertEqual(try context.count(for: PhotoEntity.fetchRequest()), 0)
        XCTAssertEqual(try context.count(for: ScanMetadataEntity.fetchRequest()), 0)
    }
}

private enum ExpectedError: Error, Equatable {
    case failure
}
