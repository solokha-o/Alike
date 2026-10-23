//
//  AppIntentsEnvironmentAdapter.swift
//  Alike
//

import AppIntentsKit
import Foundation
import WidgetSupport

/// Connects the intents in `AppIntentsKit` to the app.
///
/// Reads the reclaimable figure and the Premium flag from the widget snapshot in the
/// App Group container rather than from `CleanupWorkspaceModel`: an intent can run in
/// the background before any view has loaded the workspace, and the snapshot is the
/// same aggregate the home-screen widget shows, so Siri and the widget cannot disagree.
/// Navigation goes through `PendingWidgetDestination`, the holder a widget tap uses,
/// so an intent lands exactly where the equivalent widget link would — including the
/// Premium gate inside `CleanupView`.
final class AppIntentsEnvironmentAdapter: AppIntentsEnvironmentProviding, Sendable {
    private let snapshotReader: (any WidgetSnapshotReading)?
    private let pendingDestination: PendingWidgetDestination

    init(
        snapshotReader: (any WidgetSnapshotReading)? = WidgetSnapshotStore(),
        pendingDestination: PendingWidgetDestination
    ) {
        self.snapshotReader = snapshotReader
        self.pendingDestination = pendingDestination
    }

    func reclaimableSummary() async -> ReclaimableSummary? {
        guard let snapshot = snapshotReader?.read(), snapshot.hasCompletedScan else { return nil }
        return ReclaimableSummary(
            totalBytes: snapshot.estimatedSavingsBytes ?? 0,
            clusterCount: snapshot.clusterCount,
            lastScanDate: snapshot.lastScanDate
        )
    }

    func hasProAccess(to category: ClusterReviewCategory) async -> Bool {
        guard category.requiresPro else { return true }
        return snapshotReader?.read()?.isPremium ?? false
    }

    @MainActor
    func open(_ destination: IntentDestination) {
        pendingDestination.handle(WidgetDestination(destination).url)
    }
}

extension WidgetDestination {
    /// One case per case, so adding a destination on either side is a compile error here
    /// rather than a link that silently goes nowhere.
    init(_ destination: IntentDestination) {
        self = switch destination {
        case .scan: .scan
        case .cleanup: .cleanup
        case .resumeReview: .resumeReview
        case .similarPhotos: .similarPhotos
        case .screenshots: .screenshots
        case .blurredPhotos: .blurredPhotos
        }
    }
}
