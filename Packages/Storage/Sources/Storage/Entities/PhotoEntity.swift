import CoreData
import Foundation

@objc(PhotoEntity)
public final class PhotoEntity: NSManagedObject {
    @NSManaged public var localIdentifier: String
    @NSManaged public var featurePrintData: Data?
    @NSManaged public var creationDate: Date?
    @NSManaged public var modificationDate: Date?
    @NSManaged public var pixelWidth: Int32
    @NSManaged public var pixelHeight: Int32
    @NSManaged public var isFavorite: Bool
    @NSManaged public var cluster: ClusterEntity?
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PhotoEntity> {
        return NSFetchRequest<PhotoEntity>(entityName: "PhotoEntity")
    }
}
