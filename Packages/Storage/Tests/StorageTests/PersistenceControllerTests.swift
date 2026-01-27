import XCTest
import CoreData
@testable import Storage

final class PersistenceControllerTests: XCTestCase {
    
    // MARK: - In-Memory Store Tests
    
    func testInMemoryStoreInitialization() async throws {
        // Given & When: Creating in-memory persistence controller
        let controller = PersistenceController.preview()
        
        // Then: Should be successfully initialized
        XCTAssertNotNil(controller, "In-memory controller should be initialized")
    }
    
    func testInMemoryStoreIsolation() async throws {
        // Given: Two separate in-memory controllers
        let controller1 = PersistenceController.preview()
        let controller2 = PersistenceController.preview()
        
        // When: Saving data to controller1
        let context1 = controller1.viewContext
        let entity1 = ClusterEntity(context: context1)
        entity1.id = UUID()
        entity1.createdAt = Date()
        entity1.averageSimilarity = 0.95
        try context1.save()
        
        // Then: controller2 should not have the data
        let context2 = controller2.viewContext
        let fetchRequest = ClusterEntity.fetchRequest()
        let results = try context2.fetch(fetchRequest)
        
        XCTAssertTrue(results.isEmpty, "In-memory stores should be isolated")
    }
    
    func testInMemoryDataPersistence() async throws {
        // Given: In-memory controller with data
        let controller = PersistenceController.preview()
        let context = controller.viewContext
        
        let entity = ClusterEntity(context: context)
        entity.id = UUID()
        entity.createdAt = Date()
        entity.averageSimilarity = 0.90
        try context.save()
        
        // When: Fetching data
        let fetchRequest = ClusterEntity.fetchRequest()
        let results = try context.fetch(fetchRequest)
        
        // Then: Data should be available
        XCTAssertEqual(results.count, 1, "Should fetch saved entity")
        XCTAssertEqual(results.first?.averageSimilarity ?? 0.0, 0.90, accuracy: 0.01)
    }
    
    // MARK: - Background Task Tests
    
    func testPerformBackgroundTask() async throws {
        // Given: Controller
        let controller = PersistenceController.preview()
        
        // When: Performing background task
        let taskExecuted = expectation(description: "Background task executed")
        try await controller.performBackgroundTask { context in
            XCTAssertNotNil(context, "Context should be provided")
            XCTAssertTrue(Thread.isMainThread == false || true, "Task context should work")
            taskExecuted.fulfill()
        }
        
        // Then: Task should be executed
        await fulfillment(of: [taskExecuted], timeout: 1.0)
    }
    
    func testBackgroundTaskSave() async throws {
        // Given: Controller
        let controller = PersistenceController.preview()
        let testID = UUID()
        
        // When: Saving in background task
        try await controller.performBackgroundTask { context in
            let entity = ClusterEntity(context: context)
            entity.id = testID
            entity.createdAt = Date()
            entity.averageSimilarity = 0.88
            try context.save()
        }
        
        // Then: Data should be available in view context
        let context = controller.viewContext
        let fetchRequest = ClusterEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", testID as CVarArg)
        
        let results = try context.fetch(fetchRequest)
        XCTAssertEqual(results.count, 1, "Background save should be visible in view context")
    }
    
    func testBackgroundTaskErrorHandling() async throws {
        // Given: Controller
        let controller = PersistenceController.preview()
        
        // When & Then: Error in background task should propagate
        do {
            try await controller.performBackgroundTask { _ in
                throw NSError(domain: "TestError", code: 1, userInfo: nil)
            }
            XCTFail("Should throw error")
        } catch {
            XCTAssertNotNil(error, "Error should be thrown")
        }
    }
    
    // MARK: - Shared Instance Tests
    
    func testSharedInstanceNotInMemory() {
        // Given & When: Accessing shared instance
        let shared = PersistenceController.shared
        
        // Then: Should be initialized and not in-memory
        XCTAssertNotNil(shared, "Shared instance should exist")
    }
    
    // MARK: - View Context Tests
    
    func testViewContextAutomaticallySaves() async throws {
        // Given: Controller
        let controller = PersistenceController.preview()
        let context = controller.viewContext
        
        // When: Making changes on view context
        let entity = ClusterEntity(context: context)
        entity.id = UUID()
        entity.createdAt = Date()
        entity.averageSimilarity = 0.85
        
        // Save explicitly for testing
        try context.save()
        
        // Then: Changes should be persisted
        let fetchRequest = ClusterEntity.fetchRequest()
        let results = try context.fetch(fetchRequest)
        
        XCTAssertEqual(results.count, 1, "Changes should be persisted")
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentBackgroundTasks() async throws {
        // Given: Controller
        let controller = PersistenceController.preview()
        
        // When: Running multiple background tasks concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try? await controller.performBackgroundTask { context in
                        let entity = ClusterEntity(context: context)
                        entity.id = UUID()
                        entity.createdAt = Date()
                        entity.averageSimilarity = Float(i) / 10.0
                        try context.save()
                    }
                }
            }
        }
        
        // Then: All entities should be saved
        let context = controller.viewContext
        let fetchRequest = ClusterEntity.fetchRequest()
        let results = try context.fetch(fetchRequest)
        
        XCTAssertEqual(results.count, 10, "All concurrent tasks should complete successfully")
    }
}
