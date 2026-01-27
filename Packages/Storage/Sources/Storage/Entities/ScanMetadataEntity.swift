import CoreData
import Foundation

@objc(ScanMetadataEntity)
public final class ScanMetadataEntity: NSManagedObject {
    @NSManaged public var lastScanDate: Date?
    @NSManaged public var totalPhotosScanned: Int32
    @NSManaged public var photoLibraryChangeToken: String?
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ScanMetadataEntity> {
        return NSFetchRequest<ScanMetadataEntity>(entityName: "ScanMetadataEntity")
    }
}
