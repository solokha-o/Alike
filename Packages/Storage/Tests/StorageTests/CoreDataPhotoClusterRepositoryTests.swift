import XCTest
import CoreData
import Photos
import Core
@testable import Storage

@MainActor
final class CoreDataPhotoClusterRepositoryTests: XCTestCase {
    var repository: CoreDataPhotoClusterRepository!
    var inMemoryController: PersistenceController!
    
    override func setUp() async throws {
        // Create in-memory store for testing
        inMemoryController = PersistenceController.preview()
        repository = CoreDataPhotoClusterRepository(persistence: inMemoryController)
    }
    
    override func tearDown() async throws {
        repository = nil
        inMemoryController = nil
    }
    
    // MARK: - Save and Load Tests
    
    func testSaveAndLoadClusters() async throws {
        // Given: Sample clusters
        let cluster1 = try createMockPhotoCluster(photoCount: 3)
        let cluster2 = try createMockPhotoCluster(photoCount: 5)
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
        let initialCluster = try createMockPhotoCluster(photoCount: 2)
        try await repository.saveClusters([initialCluster])
        
        // When: Saving new clusters (should overwrite)
        let newCluster = try createMockPhotoCluster(photoCount: 4)
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
        let cluster = try createMockPhotoCluster(photoCount: 3)
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
    
    func testUpdateScanMetadataCollapsesDuplicateRows() async throws {
        // Given: Two metadata rows, as an interrupted write could leave behind
        let context = inMemoryController.viewContext
        try await context.perform {
            let older = ScanMetadataEntity(context: context)
            older.lastScanDate = Date(timeIntervalSince1970: 1_000)
            let newer = ScanMetadataEntity(context: context)
            newer.lastScanDate = Date(timeIntervalSince1970: 2_000)
            try context.save()
        }

        // When: Writing a new baseline
        let scanDate = Date(timeIntervalSince1970: 3_000)
        try await repository.updateScanMetadata(
            ScanMetadataSnapshot(lastScanDate: scanDate, imageAssetCount: 7)
        )

        // Then: One row remains and it holds the newest baseline
        let rowCount = try await context.perform {
            try context.count(for: ScanMetadataEntity.fetchRequest())
        }
        XCTAssertEqual(rowCount, 1, "Duplicate metadata rows should be collapsed")

        let metadata = await repository.loadScanMetadata()
        XCTAssertEqual(metadata?.lastScanDate.timeIntervalSince1970, 3_000)
        XCTAssertEqual(metadata?.imageAssetCount, 7)
    }

    func testUpdateScanMetadataWithNilClearsBaseline() async throws {
        try await repository.updateLastScanDate(Date())

        try await repository.updateScanMetadata(nil)

        let metadata = await repository.loadScanMetadata()
        XCTAssertNil(metadata, "Passing nil should clear the scan baseline")
    }

    func testScanMetadataRoundTripsChangeToken() async throws {
        let token = Data([0x01, 0x02, 0x03])
        let snapshot = ScanMetadataSnapshot(
            lastScanDate: Date(timeIntervalSince1970: 5_000),
            libraryChangeToken: token,
            imageAssetCount: 42
        )

        try await repository.updateScanMetadata(snapshot)

        let loaded = await repository.loadScanMetadata()
        XCTAssertEqual(loaded?.libraryChangeToken, token)
        XCTAssertEqual(loaded?.imageAssetCount, 42)
    }

    // MARK: - Gallery Change Detection Tests

    func testHasGalleryChangedWhenNoScanExists() async throws {
        // Given: No previous scan

        // When: Checking for changes
        let hasChanged = await repository.hasGalleryChanged()

        // Then: Should return true (needs initial scan)
        XCTAssertTrue(hasChanged, "Should indicate change when no previous scan exists")
    }

    /// The reported bug: a scan finishes, nothing is added or removed, and the
    /// Cleanup tab immediately asks for a rescan because assets were *touched*.
    func testHasGalleryChangedIsFalseWhenAssetsWereOnlyModified() async throws {
        let detector = FakeChangeDetector(
            token: Data([0xAA]),
            imageAssetCount: 120,
            summary: .none
        )
        let repository = CoreDataPhotoClusterRepository(
            persistence: inMemoryController,
            changeDetector: detector
        )
        try await repository.updateScanMetadata(
            await repository.captureScanMetadata(completedAt: Date())
        )

        let hasChanged = await repository.hasGalleryChanged()

        XCTAssertFalse(hasChanged, "Metadata-only changes must not request a rescan")
    }

    func testHasGalleryChangedIsTrueWhenImagesWereInserted() async throws {
        let detector = FakeChangeDetector(
            token: Data([0xAA]),
            imageAssetCount: 120,
            summary: PhotoLibraryChangeSummary(insertedImageCount: 2, hasDeletions: false)
        )
        let repository = CoreDataPhotoClusterRepository(
            persistence: inMemoryController,
            changeDetector: detector
        )
        try await repository.updateScanMetadata(
            await repository.captureScanMetadata(completedAt: Date())
        )

        let hasChanged = await repository.hasGalleryChanged()

        XCTAssertTrue(hasChanged, "Newly inserted images should request a rescan")
    }

    func testHasGalleryChangedIgnoresDeletionsThatDoNotChangeImageCount() async throws {
        // A deleted video: history reports a deletion, the image count is intact.
        let detector = FakeChangeDetector(
            token: Data([0xAA]),
            imageAssetCount: 120,
            summary: PhotoLibraryChangeSummary(insertedImageCount: 0, hasDeletions: true)
        )
        let repository = CoreDataPhotoClusterRepository(
            persistence: inMemoryController,
            changeDetector: detector
        )
        try await repository.updateScanMetadata(
            await repository.captureScanMetadata(completedAt: Date())
        )

        let hasChanged = await repository.hasGalleryChanged()

        XCTAssertFalse(hasChanged, "A deletion that leaves the image count intact is not a change")
    }

    func testHasGalleryChangedUsesCountFallbackWhenTokenIsUnusable() async throws {
        let detector = FakeChangeDetector(
            token: Data([0xAA]),
            imageAssetCount: 120,
            summary: nil
        )
        let repository = CoreDataPhotoClusterRepository(
            persistence: inMemoryController,
            changeDetector: detector
        )
        try await repository.updateScanMetadata(
            await repository.captureScanMetadata(completedAt: Date())
        )

        var hasChanged = await repository.hasGalleryChanged()
        XCTAssertFalse(hasChanged, "An expired token with an unchanged count is not a change")

        detector.currentImageAssetCount = 121
        hasChanged = await repository.hasGalleryChanged()
        XCTAssertTrue(hasChanged, "An expired token with a changed count is a change")
    }

    func testHasGalleryChangedRequestsOneTimeRescanForLegacyBaselineWithoutToken() async throws {
        // Given: A baseline written before change tracking existed, so there is
        // no trustworthy historical fingerprint to migrate from. Changes made
        // between the legacy scan and now would be silently folded into any
        // fingerprint captured today, so a rescan must be requested instead.
        let detector = FakeChangeDetector(
            token: Data([0xBB]),
            imageAssetCount: 30,
            summary: .none
        )
        let repository = CoreDataPhotoClusterRepository(
            persistence: inMemoryController,
            changeDetector: detector
        )
        let legacyDate = Date(timeIntervalSince1970: 9_000)
        try await repository.updateLastScanDate(legacyDate)

        // When: Checking for changes
        let hasChanged = await repository.hasGalleryChanged()

        // Then: A one-time rescan is requested rather than silently adopting
        // today's library state as the historical baseline.
        XCTAssertTrue(hasChanged, "A missing legacy token must request a one-time rescan")
        let metadata = await repository.loadScanMetadata()
        XCTAssertNil(
            metadata?.libraryChangeToken,
            "The legacy baseline must not be backfilled from an untrustworthy fingerprint"
        )
        XCTAssertEqual(
            try XCTUnwrap(metadata).lastScanDate.timeIntervalSince1970,
            legacyDate.timeIntervalSince1970,
            accuracy: 1.0,
            "Requesting a rescan must not alter the stored baseline"
        )
    }

    // MARK: - Cluster Property Tests
    
    func testClusterAverageSimilarity() async throws {
        // Given: Cluster with specific average similarity
        let cluster = try createMockPhotoCluster(
            photoCount: 3,
            averageSimilarity: 0.92
        )
        
        // When: Saving and loading
        try await repository.saveClusters([cluster])
        let loadedClusters = try await repository.loadClusters()
        
        // Then: Average similarity should be preserved
        XCTAssertEqual(
            loadedClusters.first?.averageSimilarity ?? 0,
            0.92 as Float,
            accuracy: 0.01 as Float,
            "Average similarity should be preserved"
        )
    }
    
    func testClusterCreatedDate() async throws {
        // Given: Cluster with specific creation date
        let createdDate = Date()
        let cluster = try createMockPhotoCluster(
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
    ) throws -> PhotoCluster {
        // Fetch real PHAssets for testing
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = photoCount
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        guard assets.count == photoCount else {
            throw XCTSkip("Test requires at least \(photoCount) photos in the library; found \(assets.count).")
        }
        
        return PhotoCluster(
            assets: assets,
            createdAt: createdAt,
            averageSimilarity: averageSimilarity
        )
    }
}

/// Stands in for PhotoKit so change interpretation is testable without a
/// library the test can mutate.
private final class FakeChangeDetector: PhotoLibraryChangeDetecting, @unchecked Sendable {
    var token: Data?
    var currentImageAssetCount: Int
    var summary: PhotoLibraryChangeSummary?

    init(token: Data?, imageAssetCount: Int, summary: PhotoLibraryChangeSummary?) {
        self.token = token
        self.currentImageAssetCount = imageAssetCount
        self.summary = summary
    }

    func currentToken() -> Data? { token }

    func imageAssetCount() -> Int { currentImageAssetCount }

    func changes(since token: Data) -> PhotoLibraryChangeSummary? { summary }
}
