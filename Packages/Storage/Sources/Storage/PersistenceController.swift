import CoreData
import Foundation

/// Actor that manages CoreData persistence
public actor PersistenceController: Sendable {
    public static let shared = PersistenceController()
    
    private let container: NSPersistentContainer
    
    public nonisolated var viewContext: NSManagedObjectContext {
        container.viewContext
    }
    
    private init(inMemory: Bool = false) {
        guard let modelURL = Bundle.module.url(forResource: "AlikeModel", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load Core Data model")
        }
        
        container = NSPersistentContainer(name: "AlikeModel", managedObjectModel: model)

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
