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

/// `deleteAllSearchableItems` did not resume its continuation on the iOS 27.0 simulator
/// even though CoreSpotlight logged `delete-all … result: success`. The Delete Alike
/// Data flow must not hang on that, so the wait is bounded; on timeout the request has
/// already been handed to the index daemon, which journals it.
public struct SpotlightIndexClearTimeout: Error, Equatable {
    public let timeout: Duration
}

public struct SystemSpotlightIndexClearer: SpotlightIndexClearing {
    public static let defaultTimeout: Duration = .seconds(5)

    private let timeout: Duration
    private let deleteAll: @Sendable () async throws -> Void

    public init(timeout: Duration = SystemSpotlightIndexClearer.defaultTimeout) {
        self.init(timeout: timeout) {
            try await CSSearchableIndex.default().deleteAllSearchableItems()
        }
    }

    init(timeout: Duration, deleteAll: @escaping @Sendable () async throws -> Void) {
        self.timeout = timeout
        self.deleteAll = deleteAll
    }

    public func clearIndex() async throws {
        let timeout = self.timeout
        let deleteAll = self.deleteAll
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await deleteAll() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw SpotlightIndexClearTimeout(timeout: timeout)
            }
            defer { group.cancelAll() }
            try await group.next()
        }
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
