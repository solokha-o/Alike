import CoreData
import XCTest
@testable import Storage

/// Baseline for every future schema change.
///
/// `AlikeModel.xcdatamodeld` is versioned and version 1 is frozen, so a store
/// written by version 1 must keep opening against whatever model the app ships.
/// `PersistenceController` turns a failed load into `fatalError`, which means a
/// migration this test would catch reaches users as a launch crash instead.
///
/// `Fixtures/AlikeModelV1.sqlite` is a real store written by the version 1
/// model, holding one cluster and one photo. When a version 2 model lands, this
/// test starts exercising a genuine version 1 -> version 2 migration without any
/// change; add a new fixture per shipped version that is still in the field.
final class ModelVersionMigrationTests: XCTestCase {

    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ModelVersionMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let storeDirectory {
            try? FileManager.default.removeItem(at: storeDirectory)
        }
        storeDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Baseline

    func testStoreWrittenByModelVersion1StillOpensWithTheShippedModel() throws {
        // Given: a copy of the version 1 fixture store, because loading migrates
        // the file in place and a resource must never be mutated
        let storeURL = try copyFixtureStore()

        // When: it is opened with the model the app ships, using the same
        // migration settings as PersistenceController
        let container = try loadContainer(at: storeURL)
        let context = container.viewContext

        // Then: the rows written by version 1 are still there
        let clusters = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "ClusterEntity"))
        XCTAssertEqual(clusters.count, 1, "The version 1 cluster did not survive the migration")
        XCTAssertEqual(
            clusters.first?.value(forKey: "id") as? UUID,
            UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        )

        let photos = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "PhotoEntity"))
        XCTAssertEqual(photos.count, 1, "The version 1 photo did not survive the migration")
        XCTAssertEqual(photos.first?.value(forKey: "localIdentifier") as? String, "fixture/version-1")
        XCTAssertNotNil(photos.first?.value(forKey: "cluster"), "The photo lost its cluster relationship")

        try tearDown(container)
    }

    /// Guards the versioning itself: dropping `.xccurrentversion` or the version
    /// identifier would put the model back to being unversioned, which is the
    /// state this baseline exists to prevent.
    func testShippedModelDeclaresItsVersionIdentifier() throws {
        let modelURL = try XCTUnwrap(
            PersistenceController.shippedModelURL,
            "Shipped model is missing from the Storage bundle"
        )
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))

        let identifiers = model.versionIdentifiers.compactMap { $0 as? String }
        XCTAssertFalse(
            identifiers.isEmpty,
            "The shipped model declares no version identifier; every model version must set one"
        )
    }

    // MARK: - Helpers

    private func copyFixtureStore() throws -> URL {
        let fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "AlikeModelV1", withExtension: "sqlite"),
            "Version 1 fixture store is missing from the test bundle"
        )
        let storeURL = storeDirectory.appendingPathComponent("AlikeModel.sqlite")
        try FileManager.default.copyItem(at: fixture, to: storeURL)
        return storeURL
    }

    private func loadContainer(at url: URL) throws -> NSPersistentContainer {
        let modelURL = try XCTUnwrap(PersistenceController.shippedModelURL)
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))

        let container = NSPersistentContainer(name: "AlikeModel", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            XCTFail("The store failed to load, which is a launch crash in production: \(loadError)")
            throw loadError
        }
        return container
    }

    private func tearDown(_ container: NSPersistentContainer) throws {
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }
}
