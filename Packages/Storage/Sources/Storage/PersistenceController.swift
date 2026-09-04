import CoreData
import Foundation

/// Actor that manages CoreData persistence
public actor PersistenceController: Sendable {
    public static let shared = PersistenceController()
    
    private let container: NSPersistentContainer
    
    public nonisolated var viewContext: NSManagedObjectContext {
        container.viewContext
    }
    
    /// Compiled model this release ships, version 1 of `AlikeModel.xcdatamodeld`.
    ///
    /// Loaded once and shared by every container. Two `NSManagedObjectModel`
    /// instances describing the same entities make `+[ClusterEntity entity]`
    /// ambiguous, so each `preview()` used to add another instance and another
    /// round of "Failed to find a unique match" errors. It is also what the
    /// migration baseline test opens, so the test sees exactly what ships.
    ///
    /// `nonisolated(unsafe)` because `NSManagedObjectModel` is not `Sendable`:
    /// the instance is built once here and never mutated afterwards, and Core
    /// Data itself expects one model to back many coordinators.
    nonisolated(unsafe) static let shippedModel: NSManagedObjectModel = {
        guard let modelURL = Bundle.module.url(forResource: "AlikeModel", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load Core Data model")
        }
        return model
    }()

    private init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "AlikeModel", managedObjectModel: Self.shippedModel)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.persistentStoreDescriptions.first?.shouldMigrateStoreAutomatically = true
        container.persistentStoreDescriptions.first?.shouldInferMappingModelAutomatically = true
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Core Data store failed to load: \(error.localizedDescription)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }
    
    /// Create an in-memory instance for testing/previews
    public static func preview() -> PersistenceController {
        PersistenceController(inMemory: true)
    }
    
    /// Perform background task
    public func performBackgroundTask<T>(_ block: @escaping @Sendable (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                do {
                    let result = try block(context)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Save context if there are changes
    public func save(_ context: NSManagedObjectContext) async throws {
        guard context.hasChanges else { return }
        
        try await context.perform {
            try context.save()
        }
    }
    
    /// Delete all data
    public func deleteAllData() async throws {
        let deletedObjectIDs = try await performBackgroundTask { context in
            let entities = ["ClusterEntity", "PhotoEntity", "ScanMetadataEntity"]
            var deletedObjectIDs: [NSManagedObjectID] = []
            
            for entityName in entities {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                deleteRequest.resultType = .resultTypeObjectIDs
                let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
                deletedObjectIDs.append(contentsOf: result?.result as? [NSManagedObjectID] ?? [])
            }

            return deletedObjectIDs
        }

        await viewContext.perform { [viewContext] in
            if !deletedObjectIDs.isEmpty {
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSDeletedObjectsKey: deletedObjectIDs],
                    into: [viewContext]
                )
            }
            viewContext.reset()
        }
    }
}
