//
//  WidgetSnapshotPublisher.swift
//  Alike
//

import Cleanup
import Core
import Foundation
import os
import Photos
import WidgetKit
import WidgetSupport

/// Turns the app's live state into the aggregate the widget extension reads.
///
/// This lives in the app target because it is the only place that knows both halves:
/// `WidgetSupport` deliberately depends on nothing, so it cannot see `ScanSummary` or
/// `CleanupSession`, and the extension deliberately links neither `Cleanup` nor
/// `Purchases`. The mapping meets in the middle, here.
@MainActor
final class WidgetSnapshotPublisher {
    /// Owns the "unchanged payloads are not republished, failed writes are not
    /// remembered" rules, in the package where they are covered by tests.
    private let writer: DeduplicatingWidgetSnapshotWriter?
    private let reloadTimelines: @Sendable () -> Void
    private let now: () -> Date

    private static let logger = Logger(subsystem: "com.alike.app", category: "WidgetSnapshot")

    init(
        store: (any WidgetSnapshotWriting)? = WidgetSnapshotStore(),
        reloadTimelines: @escaping @Sendable () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotPublisher.widgetKind)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.writer = store.map(DeduplicatingWidgetSnapshotWriter.init(store:))
        self.reloadTimelines = reloadTimelines
        self.now = now
    }

    /// Kept in sync by hand with `AlikeStatusWidget.kind` — the app target and the
    /// extension target share no code that could hold it, since `WidgetSupport` has no
    /// WidgetKit dependency.
    nonisolated static let widgetKind = "AlikeStatusWidget"

    func publish(
        workspace: CleanupWorkspaceModel,
        authorization: PHAuthorizationStatus,
        isPremium: Bool
    ) {
        let summary = workspace.lastScanSummary
        let categories = workspace.cleanupCategories
        let clusters = workspace.clusters
        let hasCompletedScan = workspace.hasCompletedScanBaseline

        // `lastScanSummary` only survives for a scan this process ran. After a cold
        // launch the workspace restores its clusters and categories from the cache but
        // not the summary, so reading the aggregates straight off `summary` would put
        // "all caught up" on the home screen over candidates that are still there.
        let restoredSavingsBytes: Int64? = summary == nil && hasCompletedScan
            ? Self.estimatedSavingsBytes(clusters: clusters, categories: categories)
            : nil

        let snapshot = WidgetSnapshot(
            generatedAt: now(),
            photoAuthorization: WidgetPhotoAuthorization(authorization),
            hasCompletedScan: hasCompletedScan,
            lastScanDate: summary?.completedAt ?? workspace.lastCompletedScanDate,
            libraryChangedSinceScan: workspace.shouldShowRescanPrompt,
            // Taken from the scan summary rather than recomputed, so the widget cannot
            // report a different figure from the scanner screen.
            estimatedSavingsBytes: summary?.estimatedSavingsBytes ?? restoredSavingsBytes,
            // Only meaningful once a scan baseline exists; before that the count is
            // unknown rather than zero, and the widget says so.
            clusterCount: hasCompletedScan ? clusters.count : nil,
            screenshotAssetCount: categories.first { $0.kind == .screenshots }?.assetCount,
            blurredPhotoAssetCount: categories.first { $0.kind == .blurredPhotos }?.assetCount,
            isPremium: isPremium,
            sessionProgress: workspace.activeCleanupSession.map {
                WidgetSessionProgress(
                    reviewedClusters: $0.reviewedClusters,
                    totalClusters: $0.totalClusters,
                    updatedAt: $0.updatedAt
                )
            }
        )

        // Driven by a `task(id:)` carrying the scene phase, so this runs on every
        // foreground and background transition — see `hasSameContent(as:)` for why an
        // unchanged payload is not republished.
        write { try $0.write(snapshot) == .written }
    }

    /// Called after the user deletes their local data. Removing the payload is not
    /// optional: leaving it behind would keep a count of the photos they just asked
    /// the app to forget on their home screen.
    func clear() {
        write {
            try $0.clear()
            return true
        }
    }

    /// Mirrors `ScanSummary.estimatedSavingsBytes` — the same clusters-plus-categories
    /// sum `ScanPostProcessor.scanAggregates` makes — for the cold-launch case where
    /// the summary was not restored alongside the content it was computed from. Same
    /// inputs, same figure, so the widget still cannot disagree with the scanner screen.
    private static func estimatedSavingsBytes(
        clusters: [PhotoCluster],
        categories: [CleanupCategorySummary]
    ) -> Int64 {
        let clusterSavings = clusters.reduce(into: Int64(0)) { total, cluster in
            total += cluster.assets.reduce(into: Int64(0)) { $0 += $1.estimatedCleanupBytes }
        }
        return categories.reduce(into: clusterSavings) { $0 += $1.estimatedSavingsBytes }
    }

    /// Runs one store operation, reloading the timeline only when it says something
    /// reached the shared container.
    private func write(_ operation: (DeduplicatingWidgetSnapshotWriter) throws -> Bool) {
        guard let writer else {
            // No App Group container — the entitlement is missing or the group is not
            // provisioned on this build. The widget shows "open the app"; nothing else
            // in the app is affected, so this is a log, not an error path.
            Self.logger.notice("No shared container; skipping widget snapshot publish.")
            return
        }
        do {
            guard try operation(writer) else { return }
            reloadTimelines()
        } catch {
            Self.logger.error(
                "\(AppLog.tag(.error, "Failed to publish widget snapshot: \(error.localizedDescription)"))"
            )
        }
    }
}

extension WidgetPhotoAuthorization {
    /// The whole status, not `isAuthorized`.
    ///
    /// `PhotoPermissionManagerImpl.isAuthorized` folds `.limited` into `.authorized`,
    /// which is right for "may we scan" and wrong for the widget: a limited library
    /// needs different wording from a full one, and a denied library needs a different
    /// call to action from one that was never asked.
    init(_ status: PHAuthorizationStatus) {
        self = switch status {
        case .authorized: .authorized
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        // `PHAuthorizationStatus` is an Objective-C enum and can gain cases; treating an
        // unknown one as "not asked yet" keeps the widget in a safe, honest state.
        @unknown default: .notDetermined
        }
    }
}
