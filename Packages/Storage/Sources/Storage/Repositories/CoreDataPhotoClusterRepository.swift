import CoreData
import Core
import Foundation
import Photos

/// CoreData implementation of PhotoClusterRepository
@MainActor
public final class CoreDataPhotoClusterRepository: PhotoClusterRepository {
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
    
    public func saveClusters(_ clusters: [PhotoCluster]) async throws {
        try await persistence.performBackgroundTask { context in
            // Delete existing clusters
            let deleteRequest = NSBatchDeleteRequest(
                fetchRequest: ClusterEntity.fetchRequest()
            )
            try context.execute(deleteRequest)
            
            // Save new clusters
            for cluster in clusters {
                let entity = ClusterEntity(context: context)
                entity.id = cluster.id
                entity.createdAt = cluster.createdAt
                entity.averageSimilarity = cluster.averageSimilarity
                
                for asset in cluster.assets {
                    let photoEntity = PhotoEntity(context: context)
                    photoEntity.localIdentifier = asset.localIdentifier
                    photoEntity.creationDate = asset.creationDate
                    photoEntity.modificationDate = asset.modificationDate
                    photoEntity.pixelWidth = Int32(asset.pixelWidth)
                    photoEntity.pixelHeight = Int32(asset.pixelHeight)
                    photoEntity.isFavorite = asset.isFavorite
                    
                    entity.addToPhotos(photoEntity)
                }
            }
            
            try context.save()
        }
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
}
