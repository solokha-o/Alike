import Foundation
import Testing
@testable import Storage

@MainActor
@Suite struct CoreDataPhotoClusterRepositoryDataTests {
    private let repository: CoreDataPhotoClusterRepository
    private let controller: PersistenceController

    init() {
        controller = PersistenceController.preview()
        repository = CoreDataPhotoClusterRepository(persistence: controller)
    }

    @Test func testSaveAndLoadClusterData() async throws {
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

        #expect(loaded.count == 2)
        #expect(loaded[0].assets.count == 1)
        #expect(loaded[1].assets.count == 1)
    }

    @Test func testSaveClusterDataOverwritesExisting() async throws {
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
        #expect(loaded.count == 1)
        let eps: Float = 0.001
        #expect(abs((loaded.first?.averageSimilarity ?? 0) - 0.7) <= eps)
    }

    @Test func testLoadClusterSnapshotsPreservesAssetMetadataForDiffing() async throws {
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

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.id == clusterID)
        #expect(snapshots.first?.assetIdentifiers == ["asset-a", "asset-b"])
        #expect(snapshots.first?.bestShotLocalIdentifier == "asset-a")
    }
}
