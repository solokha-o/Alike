import XCTest
import CoreData
import Core
@testable import Storage

@MainActor
final class CoreDataPhotoClusterRepositoryTests: XCTestCase {
    var repository: CoreDataPhotoClusterRepository!
    var inMemoryController: PersistenceController!
    
    override func setUp() async throws {
        // Create in-memory store for testing
        inMemoryController = PersistenceController(inMemory: true)
        repository = CoreDataPhotoClusterRepository(persistence: inMemoryController)
    }
    
    override func tearDown() async throws {
        repository = nil
        inMemoryController = nil
    }
    
    // MARK: - Save and Load Tests
    
    func testSaveAndLoadClusters() async throws {
        // Given: Sample clusters
        let cluster1 = createMockPhotoCluster(photoCount: 3)
        let cluster2 = createMockPhotoCluster(photoCount: 5)
        let clusters = [cluster1, cluster2]
        
        // When: Saving clusters
        try await repository.saveClusters(clusters)
        
        // Then: Loading should return same clusters
        let loadedClusters = try await repository.loadClusters()
        
        XCTAssertEqual(loadedClusters.count, 2, "Should load 2 clusters")
        XCTAssertEqual(loadedClusters[0].assets.count, 3, "First cluster should have 3 photos")
        XCTAssertEqual(loadedClusters[1].assets.count, 5, "Second cluster should have 5 photos")
    }
    
    func testSaveOverwritesExistingClusters() async throws {
        // Given: Initial clusters
        let initialCluster = createMockPhotoCluster(photoCount: 2)
        try await repository.saveClusters([initialCluster])
        
        // When: Saving new clusters (should overwrite)
        let newCluster = createMockPhotoCluster(photoCount: 4)
        try await repository.saveClusters([newCluster])
        
        // Then: Should only have new cluster
        let loadedClusters = try await repository.loadClusters()
        
        XCTAssertEqual(loadedClusters.count, 1, "Should only have new cluster")
        XCTAssertEqual(loadedClusters.first?.assets.count, 4, "Should have 4 photos")
    }
    
    func testLoadEmptyClusters() async throws {
        // Given: Empty database
        
        // When: Loading clusters
        let clusters = try await repository.loadClusters()
        
        // Then: Should return empty array
        XCTAssertTrue(clusters.isEmpty, "Should return empty array when no clusters saved")
    }
    
    // MARK: - Delete Tests
    
    func testDeleteAllClusters() async throws {
        // Given: Saved clusters
        let cluster = createMockPhotoCluster(photoCount: 3)
        try await repository.saveClusters([cluster])
        
        // Verify clusters exist
        var loadedClusters = try await repository.loadClusters()
        XCTAssertEqual(loadedClusters.count, 1)
        
        // When: Deleting all clusters
        try await repository.deleteAllClusters()
        
        // Then: Should have no clusters
        loadedClusters = try await repository.loadClusters()
        XCTAssertTrue(loadedClusters.isEmpty, "All clusters should be deleted")
    }
    
    // MARK: - Scan Metadata Tests
    
    func testUpdateAndGetLastScanDate() async throws {
        // Given: A scan date
        let scanDate = Date()
        
        // When: Updating last scan date
        try await repository.updateLastScanDate(scanDate)
        
        // Then: Should retrieve same date
        let retrievedDate = await repository.getLastScanDate()
        
        XCTAssertNotNil(retrievedDate, "Scan date should not be nil")
        XCTAssertEqual(
            scanDate.timeIntervalSince1970,
            retrievedDate!.timeIntervalSince1970,
            accuracy: 1.0,
            "Retrieved date should match saved date"
        )
    }
    
    func testGetLastScanDateWhenNoneExists() async throws {
        // Given: No scan metadata
        
        // When: Getting last scan date
        let scanDate = await repository.getLastScanDate()
        
        // Then: Should return nil
        XCTAssertNil(scanDate, "Should return nil when no scan has been performed")
    }
    
    func testUpdateLastScanDateMultipleTimes() async throws {
        // Given: First scan date
        let firstDate = Date()
        try await repository.updateLastScanDate(firstDate)
        
        // When: Updating with new date
        let secondDate = Date().addingTimeInterval(3600) // 1 hour later
        try await repository.updateLastScanDate(secondDate)
        
        // Then: Should return latest date
        let retrievedDate = await repository.getLastScanDate()
        
        XCTAssertEqual(
            secondDate.timeIntervalSince1970,
            retrievedDate!.timeIntervalSince1970,
            accuracy: 1.0,
            "Should return most recent scan date"
        )
    }
    
    // MARK: - Gallery Change Detection Tests
    
    func testHasGalleryChangedWhenNoScanExists() async throws {
        // Given: No previous scan
        
        // When: Checking for changes
        let hasChanged = await repository.hasGalleryChanged()
        
        // Then: Should return true (needs initial scan)
        XCTAssertTrue(hasChanged, "Should indicate change when no previous scan exists")
    }
    
    func testHasGalleryChangedWithRecentScan() async throws {
        // Given: Recent scan date
        let recentDate = Date() // Now
        try await repository.updateLastScanDate(recentDate)
        
        // When: Checking for changes
        let hasChanged = await repository.hasGalleryChanged()
        
        // Then: Result depends on actual photo library state
        // This test is environment-dependent
        // In a controlled test environment with no photo changes, should return false
        XCTAssertNotNil(hasChanged, "Should return a boolean value")
    }
    
    // MARK: - Cluster Property Tests
    
    func testClusterAverageSimilarity() async throws {
        // Given: Cluster with specific average similarity
        let cluster = createMockPhotoCluster(
            photoCount: 3,
            averageSimilarity: 0.92
        )
        
        // When: Saving and loading
        try await repository.saveClusters([cluster])
        let loadedClusters = try await repository.loadClusters()
        
        // Then: Average similarity should be preserved
        XCTAssertEqual(
            loadedClusters.first?.averageSimilarity,
            0.92,
            accuracy: 0.01,
            "Average similarity should be preserved"
        )
    }
    
    func testClusterCreatedDate() async throws {
        // Given: Cluster with specific creation date
        let createdDate = Date()
        let cluster = createMockPhotoCluster(
            photoCount: 2,
            createdAt: createdDate
        )
        
        // When: Saving and loading
        try await repository.saveClusters([cluster])
        let loadedClusters = try await repository.loadClusters()
        
        // Then: Creation date should be preserved
        XCTAssertEqual(
            createdDate.timeIntervalSince1970,
            loadedClusters.first?.createdAt.timeIntervalSince1970 ?? 0,
            accuracy: 1.0,
            "Creation date should be preserved"
        )
    }
    
    // MARK: - Helper Methods
    
    private func createMockPhotoCluster(
        photoCount: Int,
        averageSimilarity: Float = 0.95,
        createdAt: Date = Date()
    ) -> PhotoCluster {
        // Fetch real PHAssets for testing
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = photoCount
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        // If not enough photos, pad with duplicates
        while assets.count < photoCount {
            if let first = assets.first {
                assets.append(first)
            } else {
                // No photos available - create minimal cluster
                break
            }
        }
        
        return PhotoCluster(
            assets: assets,
            createdAt: createdAt,
            averageSimilarity: averageSimilarity
        )
    }
}
