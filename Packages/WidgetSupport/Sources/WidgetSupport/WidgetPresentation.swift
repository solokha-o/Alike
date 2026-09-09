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

    /// When a snapshot's figures stop being presentable as current.
    ///
    /// The extension has no way to notice the threshold passing on its own, so the
    /// timeline schedules an entry here and the widget re-renders with the timestamp
    /// instead of silently going on claiming the numbers are today's.
    public static func staleDate(for snapshot: WidgetSnapshot) -> Date {
        snapshot.generatedAt.addingTimeInterval(staleAfter)
    }

    /// The whole timeline for a snapshot: what to show now, plus the switch to the
    /// stale wording when there is one still ahead.
    ///
    /// The provider lives in the extension target, which has no test action, so the
    /// decision about how many entries there are and what each says is made here.
    /// The second entry is omitted when the state reads the same either side of the
    /// threshold — the states that carry no `isStale` do — because an entry that
    /// redraws identical pixels is not worth scheduling.
    public static func timeline(
        for snapshot: WidgetSnapshot?,
        now: Date = Date()
    ) -> [WidgetTimelineStep] {
        var steps = [WidgetTimelineStep(date: now, state: displayState(for: snapshot, now: now))]

        if let snapshot {
            let staleDate = staleDate(for: snapshot)
            let staleState = displayState(for: snapshot, now: staleDate)
            if staleDate > now, staleState != steps[0].state {
                steps.append(WidgetTimelineStep(date: staleDate, state: staleState))
            }
        }

        return steps
    }

    public static func displayState(
        for snapshot: WidgetSnapshot?,
        now: Date = Date()
    ) -> WidgetDisplayState {
        guard let snapshot else { return .unavailable }

        guard snapshot.photoAuthorization.grantsLibraryAccess else {
            return .noAccess(snapshot.photoAuthorization)
        }

        guard snapshot.hasCompletedScan else { return .neverScanned }

        // `>=`, not `>`: `staleDate(for:)` is the exact instant the timeline schedules
        // its second entry on, and that entry has to render the stale wording.
        let isStale = now.timeIntervalSince(snapshot.generatedAt) >= staleAfter

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

/// One rendering of the widget and the moment WidgetKit should switch to it.
public struct WidgetTimelineStep: Equatable, Sendable {
    public let date: Date
    public let state: WidgetDisplayState

    public init(date: Date, state: WidgetDisplayState) {
        self.date = date
        self.state = state
    }
}
