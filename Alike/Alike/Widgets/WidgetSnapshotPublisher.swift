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
    private let store: (any WidgetSnapshotWriting)?
    private let reloadTimelines: @Sendable () -> Void
    private let now: () -> Date
    /// The last payload written, so an unchanged republish costs nothing.
    private var lastWritten: WidgetSnapshot?

    private static let logger = Logger(subsystem: "com.alike.app", category: "WidgetSnapshot")

    init(
        store: (any WidgetSnapshotWriting)? = WidgetSnapshotStore(),
        reloadTimelines: @escaping @Sendable () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotPublisher.widgetKind)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
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

        let snapshot = WidgetSnapshot(
            generatedAt: now(),
            photoAuthorization: WidgetPhotoAuthorization(authorization),
            hasCompletedScan: workspace.hasCompletedScanBaseline,
            lastScanDate: summary?.completedAt,
            libraryChangedSinceScan: workspace.shouldShowRescanPrompt,
            // Taken from the scan summary rather than recomputed, so the widget cannot
            // report a different figure from the scanner screen.
            estimatedSavingsBytes: summary?.estimatedSavingsBytes,
            // Only meaningful once a scan has produced a summary; before that the
            // count is unknown rather than zero, and the widget says so.
            clusterCount: summary == nil ? nil : workspace.clusters.count,
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
        if let lastWritten, lastWritten.hasSameContent(as: snapshot) { return }

        write { try $0.write(snapshot) }
        lastWritten = snapshot
    }

    /// Called after the user deletes their local data. Removing the payload is not
    /// optional: leaving it behind would keep a count of the photos they just asked
    /// the app to forget on their home screen.
    func clear() {
        write { try $0.clear() }
        lastWritten = nil
    }

    private func write(_ operation: (any WidgetSnapshotWriting) throws -> Void) {
        guard let store else {
            // No App Group container — the entitlement is missing or the group is not
            // provisioned on this build. The widget shows "open the app"; nothing else
            // in the app is affected, so this is a log, not an error path.
            Self.logger.notice("No shared container; skipping widget snapshot publish.")
            return
        }
        do {
            try operation(store)
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
