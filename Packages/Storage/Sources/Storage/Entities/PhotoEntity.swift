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
    /// Cached Best Shot quality signals, encoded as JSON. All quality
    /// attributes are optional so the store migrates lightweight.
    @NSManaged public var qualitySignalsData: Data?
    /// Modification date of the asset the signals were measured on.
    @NSManaged public var qualitySourceModificationDate: Date?
    @NSManaged public var scoringModelVersion: Int32
    @NSManaged public var thumbnailConfigVersion: Int32
    @NSManaged public var qualityScoredAt: Date?
    /// `true` once Alike applied its own auto-enhancement, so the cached
    /// signals stay the ones measured before that edit.
    @NSManaged public var isAlikeEnhanced: Bool
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PhotoEntity> {
        return NSFetchRequest<PhotoEntity>(entityName: "PhotoEntity")
    }
}
