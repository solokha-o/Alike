import Foundation

/// What a widget should say, derived from a snapshot.
///
/// Pure data, no SwiftUI: the views live in the extension target, which has no test
/// action, so every decision about *which* state to show is made here where the
/// package's own tests can reach it.
public enum WidgetDisplayState: Equatable, Sendable {
    /// No snapshot on disk, or one this build cannot read.
    case unavailable
    /// Photos access was never requested, or was denied or restricted.
    case noAccess(WidgetPhotoAuthorization)
    /// Access granted but the library has never been scanned.
    case neverScanned
    /// Scanned, nothing left to clean.
    case allCaughtUp(scannedAt: Date?)
    /// Scanned, with suggestions waiting.
    case hasSuggestions(bytes: Int64?, clusterCount: Int?, scannedAt: Date?, isStale: Bool)
    /// The library changed since the last scan, so the figures below are historical.
    case libraryChanged(bytes: Int64?, scannedAt: Date?)
    /// A cleanup session is part-way through.
    case resumeReview(progress: WidgetSessionProgress, isStale: Bool)
}

public enum WidgetPresentation {
    /// How old a snapshot may be before its numbers are presented with a timestamp
    /// instead of as the current state of the library.
    ///
    /// The extension cannot refresh itself — the timeline policy is `.never` and only
    /// the app reloads it — so a user who has not opened Alike in days is looking at
    /// figures from the last time they did. Saying so is the honest option.
    public static let staleAfter: TimeInterval = 24 * 60 * 60

    public static func displayState(
        for snapshot: WidgetSnapshot?,
        now: Date = Date()
    ) -> WidgetDisplayState {
        guard let snapshot else { return .unavailable }

        guard snapshot.photoAuthorization.grantsLibraryAccess else {
            return .noAccess(snapshot.photoAuthorization)
        }

        guard snapshot.hasCompletedScan else { return .neverScanned }

        let isStale = now.timeIntervalSince(snapshot.generatedAt) > staleAfter

        // An unfinished session outranks the totals: someone mid-review wants the way
        // back into it more than they want a number they have already seen.
        if let progress = snapshot.sessionProgress, !progress.isComplete, progress.totalClusters > 0 {
            return .resumeReview(progress: progress, isStale: isStale)
        }

        if snapshot.libraryChangedSinceScan {
            return .libraryChanged(
                bytes: snapshot.estimatedSavingsBytes,
                scannedAt: snapshot.lastScanDate
            )
        }

        let hasSomethingToShow = (snapshot.estimatedSavingsBytes ?? 0) > 0
            || (snapshot.clusterCount ?? 0) > 0
        guard hasSomethingToShow else {
            return .allCaughtUp(scannedAt: snapshot.lastScanDate)
        }

        return .hasSuggestions(
            bytes: snapshot.estimatedSavingsBytes,
            clusterCount: snapshot.clusterCount,
            scannedAt: snapshot.lastScanDate,
            isStale: isStale
        )
    }

    /// Where a tap on the widget as a whole should land for a given state.
    public static func destination(for state: WidgetDisplayState) -> WidgetDestination {
        switch state {
        case .resumeReview: .resumeReview
        default: .cleanup
        }
    }
}
