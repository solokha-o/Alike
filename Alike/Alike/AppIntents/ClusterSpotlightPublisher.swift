//
//  ClusterSpotlightPublisher.swift
//  Alike
//

import AppIntentsKit
import Cleanup
import Core
import Foundation
import os
import Photos

/// The clusters the entity query answers from, shared between the publisher (writes)
/// and `PhotoClusterEntityQuery` (reads, from whatever thread the system calls it on).
final class ClusterIndexRecordStore: ClusterIndexSource, Sendable {
    static let shared = ClusterIndexRecordStore()

    private let records = OSAllocatedUnfairLock<[ClusterIndexRecord]>(initialState: [])

    func replace(with newRecords: [ClusterIndexRecord]) {
        records.withLock { $0 = newRecords }
    }

    func clusterRecords() async -> [ClusterIndexRecord] {
        records.withLock { $0 }
    }
}

/// Mirrors the live clusters into Spotlight after every scan, as metadata only.
///
/// Lives in the app target for the same reason `WidgetSnapshotPublisher` does: it is
/// the one place that sees both `CleanupWorkspaceModel` and `AppIntentsKit`. The
/// mapping drops everything but the four fields `ClusterIndexRecord` allows.
@MainActor
final class ClusterSpotlightPublisher {
    private let recordStore: ClusterIndexRecordStore
    private let clearer: any SpotlightIndexClearing
    /// `ClusterSpotlightIndexer` is iOS 18 API; on iOS 17 this stays `nil` and no index
    /// is ever written, while `clear()` still runs so Delete Alike Data is complete.
    private let indexer: (any Sendable)?
    private var lastPublishedRecords: [ClusterIndexRecord]?

    private static let logger = Logger(subsystem: "com.alike.app", category: "Spotlight")

    init(
        recordStore: ClusterIndexRecordStore = .shared,
        clearer: any SpotlightIndexClearing = SystemSpotlightIndexClearer()
    ) {
        self.recordStore = recordStore
        self.clearer = clearer
        if #available(iOS 18.0, *) {
            self.indexer = ClusterSpotlightIndexer(clearer: clearer)
        } else {
            self.indexer = nil
        }
    }

    /// Re-indexes when the workspace is quiet. Called from the same `task(id:)` as the
    /// widget publisher, so it sees every saved scan, review and cleanup.
    func publish(workspace: CleanupWorkspaceModel) {
        guard workspace.scanOperation == .idle, workspace.hasCompletedScanBaseline else { return }
        var records = Self.records(from: workspace)
#if DEBUG
        // The simulator cannot form clusters (Vision finds no faces, PhotoKit has no
        // duplicates), so a launch argument stands in for a scan when checking Spotlight.
        if records.isEmpty, ProcessInfo.processInfo.arguments.contains("--seed-spotlight-samples") {
            records = Self.sampleRecords
        }
#endif
        guard records != lastPublishedRecords else { return }
        lastPublishedRecords = records
        recordStore.replace(with: records)
        guard #available(iOS 18.0, *), let indexer = indexer as? ClusterSpotlightIndexer else { return }
        // Off the main actor: a library with thousands of groups must not stall the UI.
        Task.detached(priority: .utility) {
            await indexer.replaceAll(with: records)
        }
    }

    /// Called after the user deletes their local data. The index is a copy of that data
    /// outside the sandbox; leaving it would keep "12 similar photos · September" in
    /// Spotlight after the app itself has forgotten them.
    func clear() async throws {
        lastPublishedRecords = nil
        recordStore.replace(with: [])
        do {
            try await clearer.clearIndex()
        } catch let timeout as SpotlightIndexClearTimeout {
            // The request reached CoreSpotlight, which journals it; only the reply is
            // missing. Logged, not surfaced: the user's local data is already gone and a
            // failure here would read as if it were not.
            Self.logger.error(
                "\(AppLog.tag(.error, "Spotlight clear did not reply within \(timeout.timeout); continuing"))"
            )
        }
    }

    /// Same keeper and byte source as `reclaimableEstimate` and the widget's top
    /// clusters, so an entity never claims a photo the headline figure keeps.
    static func records(from workspace: CleanupWorkspaceModel) -> [ClusterIndexRecord] {
        workspace.clusters.map { cluster in
            let reclaimable = cluster.reclaimableCluster(
                keeping: workspace.reviewStates[cluster.id]?.bestShotLocalIdentifier
            )
            let bytes = reclaimable.assets
                .filter { $0.localIdentifier != reclaimable.keeperLocalIdentifier }
                .reduce(into: Int64(0)) { $0 += $1.estimatedCleanupBytes }
            let taken = cluster.assets.compactMap(\.creationDate).min() ?? cluster.createdAt
            return ClusterIndexRecord(
                id: cluster.id.uuidString,
                photoCount: cluster.count,
                reclaimableBytes: bytes,
                month: ClusterIndexRecord.month(of: taken)
            )
        }
    }

#if DEBUG
    static let sampleRecords: [ClusterIndexRecord] = {
        let calendar = Calendar.current
        let now = Date()
        return (0..<3).map { offset in
            let month = calendar.date(byAdding: .month, value: -offset, to: now) ?? now
            return ClusterIndexRecord(
                id: "sample-\(offset)",
                photoCount: 4 + offset * 3,
                reclaimableBytes: Int64(18_000_000 * (offset + 1)),
                month: ClusterIndexRecord.month(of: month)
            )
        }
    }()
#endif
}
