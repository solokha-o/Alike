//
//  WidgetSnapshotTimelineProvider.swift
//  AlikeWidgets
//

import WidgetKit
import WidgetSupport

struct WidgetSnapshotEntry: TimelineEntry {
    let date: Date
    let state: WidgetDisplayState
}

/// Reads the shared snapshot and hands WidgetKit a single entry.
///
/// The reload policy is `.never` on purpose. The extension has no data source of its
/// own — it does not scan, does not touch Core Data and does not link the photo
/// library — so a scheduled refresh would re-read an unchanged file and spend one of
/// the system's limited refresh budgets for nothing. The app calls
/// `WidgetCenter.reloadTimelines` whenever it publishes a new snapshot, which is the
/// only moment there is anything new to show.
///
/// The one change that happens without new data is the snapshot going stale, so the
/// timeline carries a second entry at that threshold. WidgetKit renders it from the
/// data it already has; no refresh budget is spent.
struct WidgetSnapshotTimelineProvider: TimelineProvider {
    private let store: (any WidgetSnapshotReading)?

    init(store: (any WidgetSnapshotReading)? = WidgetSnapshotStore()) {
        self.store = store
    }

    func placeholder(in context: Context) -> WidgetSnapshotEntry {
        WidgetSnapshotEntry(
            date: Date(),
            state: WidgetPresentation.displayState(for: .placeholder())
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetSnapshotEntry) -> Void) {
        // The widget gallery shows this one, and it has to look like something even
        // before the user has granted access or run a scan.
        let snapshot = context.isPreview ? WidgetSnapshot.placeholder() : store?.read()
        completion(WidgetSnapshotEntry(
            date: Date(),
            state: WidgetPresentation.displayState(for: snapshot)
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetSnapshotEntry>) -> Void) {
        let entries = WidgetPresentation.timeline(for: store?.read())
            .map { WidgetSnapshotEntry(date: $0.date, state: $0.state) }
        completion(Timeline(entries: entries, policy: .never))
    }
}
