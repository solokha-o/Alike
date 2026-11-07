# WidgetSupport

The data and layout that the app and the widget extension share.
The app writes a `WidgetSnapshot` to the App Group. The widget reads it and builds its presentation.
It also maps a widget tap to an `alike://` destination.

- **Category:** Foundation (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Define, store, and present the widget snapshot.
- **Main public types:** `WidgetSnapshot`, `WidgetSnapshotStore`, `DeduplicatingWidgetSnapshotWriter`, `WidgetPresentation`, `WidgetDestination`, `WidgetDisplayState`
- **Depends on:** none
- **Does not do:** Read the photo library or Core Data, or run a scan.
