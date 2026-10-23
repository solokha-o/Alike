import AppIntents
import CoreSpotlight
import Foundation

/// A group of similar photos as Spotlight and Shortcuts see it.
///
/// `IndexedEntity` is iOS 18.0, not iOS 27 as the task card assumed, so the whole
/// Spotlight half of this package is gated on iOS 18 while the deployment target
/// stays at 17. On iOS 17 the entity type does not exist and nothing is indexed.
@available(iOS 18.0, macOS 15.0, *)
public struct PhotoClusterEntity: IndexedEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("appintents.entity.photoCluster.typeName", table: "AppIntents")
    )
    public static let defaultQuery = PhotoClusterEntityQuery()

    public let id: String

    @Property(
        title: LocalizedStringResource("appintents.entity.photoCluster.photoCount", table: "AppIntents")
    )
    public var photoCount: Int

    @Property(
        title: LocalizedStringResource("appintents.entity.photoCluster.reclaimableBytes", table: "AppIntents")
    )
    public var reclaimableBytes: Int

    @Property(
        title: LocalizedStringResource("appintents.entity.photoCluster.month", table: "AppIntents")
    )
    public var month: Date

    public init(record: ClusterIndexRecord) {
        self.id = record.id
        self.photoCount = record.photoCount
        self.reclaimableBytes = Int(record.reclaimableBytes)
        self.month = record.month
    }

    public var record: ClusterIndexRecord {
        ClusterIndexRecord(
            id: id,
            photoCount: photoCount,
            reclaimableBytes: Int64(reclaimableBytes),
            month: month
        )
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(AppIntentsL10n.Entity.clusterTitle(photoCount: photoCount))",
            subtitle: "\(Self.subtitle(month: month, reclaimableBytes: reclaimableBytes))"
        )
    }

    /// Title, description and keywords only. No thumbnail, no content URL, no related
    /// identifiers: an entry must stay a sentence about counts and a month.
    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = AppIntentsL10n.Entity.clusterTitle(photoCount: photoCount)
        attributes.contentDescription = Self.subtitle(month: month, reclaimableBytes: reclaimableBytes)
        attributes.keywords = ["Alike", "similar photos", "duplicates", Self.monthFormatter.string(from: month)]
        return attributes
    }

    static func subtitle(month: Date, reclaimableBytes: Int) -> String {
        let monthText = monthFormatter.string(from: month)
        let bytesText = ByteCountFormatter.string(fromByteCount: Int64(reclaimableBytes), countStyle: .file)
        return "\(monthText) · \(bytesText)"
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter
    }()
}

/// Resolves entities by identifier and offers the current clusters as suggestions.
@available(iOS 18.0, macOS 15.0, *)
public struct PhotoClusterEntityQuery: EntityQuery {
    @Dependency
    private var source: any ClusterIndexSource

    public init() {}

    public func entities(for identifiers: [String]) async throws -> [PhotoClusterEntity] {
        let wanted = Set(identifiers)
        return await source.clusterRecords()
            .filter { wanted.contains($0.id) }
            .map(PhotoClusterEntity.init(record:))
    }

    public func suggestedEntities() async throws -> [PhotoClusterEntity] {
        await source.clusterRecords()
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
            .prefix(10)
            .map(PhotoClusterEntity.init(record:))
    }
}

public enum ClusterIndexSourceRegistration {
    /// Registers the app's cluster source so the entity query can resolve identifiers.
    public static func register(_ source: any ClusterIndexSource) {
        AppDependencyManager.shared.add(dependency: source)
    }
}
