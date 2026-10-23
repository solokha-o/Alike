import AppIntents
import Core
import CoreSpotlight
import Foundation
import os

/// Removes everything this app ever put in Spotlight.
///
/// Deliberately not gated on iOS 18: `deleteAllSearchableItems` is iOS 9 API, and the
/// Delete Alike Data flow must be able to call it on every supported OS without
/// knowing whether an index was ever written.
public protocol SpotlightIndexClearing: Sendable {
    func clearIndex() async throws
}

public struct SystemSpotlightIndexClearer: SpotlightIndexClearing {
    public init() {}

    public func clearIndex() async throws {
        try await CSSearchableIndex.default().deleteAllSearchableItems()
    }
}

/// The two Spotlight calls the indexer makes, behind a protocol so a test can count
/// batches and check which thread they arrive on.
@available(iOS 18.0, macOS 15.0, *)
public protocol SearchableEntityIndexing: Sendable {
    func index(_ entities: [PhotoClusterEntity]) async throws
    func deleteAllClusterEntities() async throws
}

@available(iOS 18.0, macOS 15.0, *)
public struct SystemSearchableEntityIndex: SearchableEntityIndexing {
    public init() {}

    public func index(_ entities: [PhotoClusterEntity]) async throws {
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }

    public func deleteAllClusterEntities() async throws {
        try await CSSearchableIndex.default().deleteAppEntities(ofType: PhotoClusterEntity.self)
    }
}

/// Writes cluster metadata into Spotlight after a scan, in batches, off the main actor.
///
/// Cluster identifiers change on every scan, so a refresh first drops every entity of
/// the type and then indexes the new set; an in-place update would leave the previous
/// scan's groups behind as ghosts.
@available(iOS 18.0, macOS 15.0, *)
public actor ClusterSpotlightIndexer: SpotlightIndexClearing {
    public static let defaultBatchSize = 100

    private let index: any SearchableEntityIndexing
    private let clearer: any SpotlightIndexClearing
    private let batchSize: Int
    private static let logger = Logger(subsystem: "com.alike.app", category: "Spotlight")

    public init(
        index: any SearchableEntityIndexing = SystemSearchableEntityIndex(),
        clearer: any SpotlightIndexClearing = SystemSpotlightIndexClearer(),
        batchSize: Int = ClusterSpotlightIndexer.defaultBatchSize
    ) {
        self.index = index
        self.clearer = clearer
        self.batchSize = max(1, batchSize)
    }

    /// Replaces the indexed clusters with `records`. An empty array empties the index.
    public func replaceAll(with records: [ClusterIndexRecord]) async {
        do {
            try await index.deleteAllClusterEntities()
            var start = records.startIndex
            while start < records.endIndex {
                let end = min(start + batchSize, records.endIndex)
                try await index.index(records[start..<end].map(PhotoClusterEntity.init(record:)))
                start = end
            }
        } catch {
            Self.logger.error(
                "\(AppLog.tag(.error, "Failed to index clusters in Spotlight: \(error.localizedDescription)"))"
            )
        }
    }

    public func clearIndex() async throws {
        try await clearer.clearIndex()
    }
}
