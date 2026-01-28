import CoreData
import Core
import Foundation
import Photos

/// CoreData implementation of PhotoClusterRepository
public final class CoreDataPhotoClusterRepository: PhotoClusterRepository {
    struct ClusterData: Sendable {
        let id: UUID
        let createdAt: Date
        let averageSimilarity: Float
        let assets: [AssetData]
    }

    struct AssetData: Sendable {
        let localIdentifier: String
        let creationDate: Date?
        let modificationDate: Date?
        let pixelWidth: Int
        let pixelHeight: Int
        let isFavorite: Bool
    }

    private let persistence: PersistenceController
    
    public init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }
    
    public func loadClusters() async throws -> [PhotoCluster] {
        let context = persistence.viewContext
        
        return try await context.perform {
            let request = ClusterEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ClusterEntity.createdAt, ascending: false)]
            
            let entities = try context.fetch(request)
            
            return entities.compactMap { entity -> PhotoCluster? in
                let localIdentifiers = entity.photosArray.map { $0.localIdentifier }
                
                // Fetch PHAssets from local identifiers
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
                var assets: [PHAsset] = []
                fetchResult.enumerateObjects { asset, _, _ in
                    assets.append(asset)
                }
                
                guard !assets.isEmpty else { return nil }
                
                return PhotoCluster(
                    id: entity.id,
                    assets: assets,
                    createdAt: entity.createdAt,
                    averageSimilarity: entity.averageSimilarity
                )
            }
        }
    }
    
    @MainActor
    public func saveClusters(_ clusters: [PhotoCluster]) async throws {
        try await saveClusterData(makeClusterData(from: clusters))
    }
    
    public func deleteAllClusters() async throws {
        try await persistence.performBackgroundTask { context in
            let deleteRequest = NSBatchDeleteRequest(
                fetchRequest: ClusterEntity.fetchRequest()
            )
            try context.execute(deleteRequest)
            try context.save()
        }
    }
    
    public func getLastScanDate() async -> Date? {
        let context = persistence.viewContext
        
        return await context.perform {
            let request = ScanMetadataEntity.fetchRequest()
            request.fetchLimit = 1
            
            guard let metadata = try? context.fetch(request).first else {
                return nil
            }
            
            return metadata.lastScanDate
        }
    }
    
    public func updateLastScanDate(_ date: Date) async throws {
        try await persistence.performBackgroundTask { context in
            let request = ScanMetadataEntity.fetchRequest()
            let metadata: ScanMetadataEntity
            
            if let existing = try context.fetch(request).first {
                metadata = existing
            } else {
                metadata = ScanMetadataEntity(context: context)
            }
            
            metadata.lastScanDate = date
            try context.save()
        }
    }
    
    public func hasGalleryChanged() async -> Bool {
        guard let lastScanDate = await getLastScanDate() else {
            return true // No previous scan
        }
        
        let context = persistence.viewContext
        
        return await context.perform {
            // Get count of photos modified after last scan
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(
                format: "modificationDate > %@",
                lastScanDate as NSDate
            )
            
            let modifiedPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            return modifiedPhotos.count > 0
        }
    }

    @MainActor
    func saveClusterData(_ clusterData: [ClusterData]) async throws {
        let viewContext = persistence.viewContext

        try await persistence.performBackgroundTask { context in
            context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
            let deleteRequest = NSBatchDeleteRequest(
                fetchRequest: ClusterEntity.fetchRequest()
            )
            deleteRequest.resultType = .resultTypeObjectIDs
            let deleteResult = try context.execute(deleteRequest) as? NSBatchDeleteResult
            if let objectIDs = deleteResult?.result as? [NSManagedObjectID], !objectIDs.isEmpty {
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                    into: [viewContext]
                )
            }

            for data in clusterData {
                let entity = ClusterEntity(context: context)
                entity.id = data.id
                entity.createdAt = data.createdAt
                entity.averageSimilarity = data.averageSimilarity

                for assetData in data.assets {
                    let photoEntity = PhotoEntity(context: context)
                    photoEntity.localIdentifier = assetData.localIdentifier
                    photoEntity.creationDate = assetData.creationDate
                    photoEntity.modificationDate = assetData.modificationDate
                    photoEntity.pixelWidth = Int32(assetData.pixelWidth)
                    photoEntity.pixelHeight = Int32(assetData.pixelHeight)
                    photoEntity.isFavorite = assetData.isFavorite

                    entity.addToPhotos(photoEntity)
                }
            }

            try context.save()
        }
    }

    func loadClusterData() async throws -> [ClusterData] {
        let context = persistence.viewContext

        return try await context.perform {
            let request = ClusterEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ClusterEntity.createdAt, ascending: false)]

            let entities = try context.fetch(request)
            return entities.map { entity in
                ClusterData(
                    id: entity.id,
                    createdAt: entity.createdAt,
                    averageSimilarity: entity.averageSimilarity,
                    assets: entity.photosArray.map { photo in
                        AssetData(
                            localIdentifier: photo.localIdentifier,
                            creationDate: photo.creationDate,
                            modificationDate: photo.modificationDate,
                            pixelWidth: Int(photo.pixelWidth),
                            pixelHeight: Int(photo.pixelHeight),
                            isFavorite: photo.isFavorite
                        )
                    }
                )
            }
        }
    }

    @MainActor
    private func makeClusterData(from clusters: [PhotoCluster]) -> [ClusterData] {
        clusters.map { cluster in
            ClusterData(
                id: cluster.id,
                createdAt: cluster.createdAt,
                averageSimilarity: cluster.averageSimilarity,
                assets: cluster.assets.map { asset in
                    AssetData(
                        localIdentifier: asset.localIdentifier,
                        creationDate: asset.creationDate,
                        modificationDate: asset.modificationDate,
                        pixelWidth: asset.pixelWidth,
                        pixelHeight: asset.pixelHeight,
                        isFavorite: asset.isFavorite
                    )
                }
            )
        }
    }
}
