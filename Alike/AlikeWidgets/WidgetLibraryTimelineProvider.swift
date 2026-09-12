//
//  WidgetLibraryTimelineProvider.swift
//  AlikeWidgets
//

import WidgetKit
import WidgetSupport

struct WidgetLibraryEntry: TimelineEntry {
    let date: Date
    let composition: WidgetLibraryComposition
}

/// The library overview's half of the shared snapshot.
///
/// A second provider rather than a second reading of `WidgetSnapshotEntry`: this widget
/// is made of the counts and the entitlement flag, and `WidgetDisplayState` carries
/// neither. Widening that shipped enum to carry them would change a type the widgets
/// already on people's home screens switch over.
///
/// Same reload policy as `WidgetSnapshotTimelineProvider`, and for the same reason:
/// `.never` plus an explicit reload from the app, because the extension has no data
/// source that could produce anything new on its own. The one change that happens
/// without new data is the figures going stale, which the second timeline entry covers
/// without spending a refresh budget.
struct WidgetLibraryTimelineProvider: TimelineProvider {
    private let store: (any WidgetSnapshotReading)?

    init(store: (any WidgetSnapshotReading)? = WidgetSnapshotStore()) {
        self.store = store
    }

    func placeholder(in context: Context) -> WidgetLibraryEntry {
        WidgetLibraryEntry(
            date: Date(),
            composition: WidgetPresentation.libraryComposition(for: .placeholder())
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetLibraryEntry) -> Void) {
        // The widget gallery shows this one, and it has to look like something even
        // before the user has granted access or run a scan.
        let snapshot = context.isPreview ? WidgetSnapshot.placeholder() : store?.read()
        completion(WidgetLibraryEntry(
            date: Date(),
            composition: WidgetPresentation.libraryComposition(for: snapshot)
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetLibraryEntry>) -> Void) {
        let entries = WidgetPresentation.libraryTimeline(for: store?.read())
            .map { WidgetLibraryEntry(date: $0.date, composition: $0.composition) }
        completion(Timeline(entries: entries, policy: .never))
    }
}
