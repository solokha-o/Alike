import CoreData
import Foundation

@objc(ClusterEntity)
public final class ClusterEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var averageSimilarity: Float
    @NSManaged public var photos: NSSet?
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ClusterEntity> {
        return NSFetchRequest<ClusterEntity>(entityName: "ClusterEntity")
    }
}

// MARK: - Generated accessors
extension ClusterEntity {
    @objc(addPhotosObject:)
    @NSManaged public func addToPhotos(_ value: PhotoEntity)
    
    @objc(removePhotosObject:)
    @NSManaged public func removeFromPhotos(_ value: PhotoEntity)
    
    @objc(addPhotos:)
    @NSManaged public func addToPhotos(_ values: NSSet)
    
    @objc(removePhotos:)
    @NSManaged public func removeFromPhotos(_ values: NSSet)
    
    public var photosArray: [PhotoEntity] {
        let set = photos as? Set<PhotoEntity> ?? []
        return Array(set).sorted { $0.localIdentifier < $1.localIdentifier }
    }
}
