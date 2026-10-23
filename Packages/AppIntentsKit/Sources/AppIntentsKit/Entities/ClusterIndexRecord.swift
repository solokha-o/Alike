import Foundation

/// A cluster reduced to what Spotlight may know about it.
///
/// Four fields, by design: the identifier, how many photos, how many bytes deleting
/// the non-keepers would free, and the month the photos were taken. No
/// `localIdentifier`, no file name, no thumbnail, no feature print — the index is a
/// second copy of user data outside the app sandbox, and the privacy policy promises
/// it stays reducible to counts and dates.
public struct ClusterIndexRecord: Sendable, Equatable, Hashable, Identifiable {
    /// The cluster's identity for the index. The spike uses `PhotoCluster.id`, which the
    /// scanner regenerates on every scan; a production build should use `contentKey`
    /// so an entity survives a rescan.
    public let id: String
    public let photoCount: Int
    public let reclaimableBytes: Int64
    /// The first day of the month the cluster's photos were taken, in the current
    /// calendar. Day and time are deliberately not kept.
    public let month: Date

    public init(id: String, photoCount: Int, reclaimableBytes: Int64, month: Date) {
        self.id = id
        self.photoCount = photoCount
        self.reclaimableBytes = reclaimableBytes
        self.month = month
    }

    /// Truncates any date to the first day of its month.
    public static func month(of date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}

/// Supplies the clusters the index should hold. Implemented by the app target over the
/// live workspace; tests supply fixtures.
public protocol ClusterIndexSource: Sendable {
    func clusterRecords() async -> [ClusterIndexRecord]
}
