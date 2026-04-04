import XCTest
@testable import Storage

@MainActor
final class CoreDataPhotoClusterRepositoryDataTests: XCTestCase {
    private var repository: CoreDataPhotoClusterRepository!
    private var controller: PersistenceController!

    override func setUp() async throws {
        controller = PersistenceController.preview()
        repository = CoreDataPhotoClusterRepository(persistence: controller)
    }

    override func tearDown() async throws {
        repository = nil
        controller = nil
    }

    func testSaveAndLoadClusterData() async throws {
        let clusterA = CoreDataPhotoClusterRepository.ClusterData(
            id: UUID(),
            createdAt: Date(),
            averageSimilarity: 0.9,
            assets: [
                .init(
                    localIdentifier: "asset-a",
                    creationDate: Date(),
                    modificationDate: nil,
                    pixelWidth: 100,
                    pixelHeight: 200,
                    isFavorite: false
                )
            ]
        )
        let clusterB = CoreDataPhotoClusterRepository.ClusterData(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-100),
            averageSimilarity: 0.8,
            assets: [
                .init(
                    localIdentifier: "asset-b",
                    creationDate: nil,
                    modificationDate: nil,
                    pixelWidth: 300,
                    pixelHeight: 400,
                    isFavorite: true
                )
            ]
        )

        try await repository.saveClusterData([clusterA, clusterB])
        let loaded = try await repository.loadClusterData()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].assets.count, 1)
        XCTAssertEqual(loaded[1].assets.count, 1)
    }

    func testSaveClusterDataOverwritesExisting() async throws {
        let first = CoreDataPhotoClusterRepository.ClusterData(
            id: UUID(),
            createdAt: Date(),
            averageSimilarity: 0.9,
            assets: []
        )
        let second = CoreDataPhotoClusterRepository.ClusterData(
            id: UUID(),
            createdAt: Date(),
            averageSimilarity: 0.7,
            assets: []
        )

        try await repository.saveClusterData([first])
        try await repository.saveClusterData([second])

        let loaded = try await repository.loadClusterData()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.averageSimilarity ?? 0, 0.7, accuracy: 0.001)
    }

    func testLoadClusterSnapshotsPreservesAssetMetadataForDiffing() async throws {
        let clusterID = UUID()
        let createdAt = Date(timeIntervalSince1970: 100)
        let modifiedAt = Date(timeIntervalSince1970: 200)
        let cluster = CoreDataPhotoClusterRepository.ClusterData(
            id: clusterID,
            createdAt: createdAt,
            averageSimilarity: 0.95,
            assets: [
                .init(
                    localIdentifier: "asset-a",
                    creationDate: createdAt,
                    modificationDate: modifiedAt,
                    pixelWidth: 1200,
                    pixelHeight: 800,
                    isFavorite: true
                ),
                .init(
                    localIdentifier: "asset-b",
                    creationDate: nil,
                    modificationDate: nil,
                    pixelWidth: 600,
                    pixelHeight: 400,
                    isFavorite: false
                )
            ]
        )

        try await repository.saveClusterData([cluster])
        let snapshots = try await repository.loadClusterSnapshots()

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.id, clusterID)
        XCTAssertEqual(snapshots.first?.assetIdentifiers, ["asset-a", "asset-b"])
        XCTAssertEqual(snapshots.first?.bestShotLocalIdentifier, "asset-a")
    }
}
