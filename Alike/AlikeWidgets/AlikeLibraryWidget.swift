//
//  AlikeLibraryWidget.swift
//  AlikeWidgets
//

import SwiftUI
import WidgetKit
import WidgetSupport

/// Concept №4, "Огляд бібліотеки": what is in the library, by category, with a way into
/// each one.
///
/// A separate `Widget` rather than a third family on `AlikeStatusWidget`. That one
/// applies a single `widgetURL` and one `accessibilityElement(children: .ignore)` to the
/// whole widget, which is exactly what three independent `Link` rows cannot live under.
/// Two entries in the gallery is also the honest presentation: they answer different
/// questions.
struct AlikeLibraryWidget: Widget {
    /// Frozen once released: `WidgetCenter.reloadTimelines(ofKind:)` in the app
    /// addresses the widget by this string.
    static let kind = "AlikeLibraryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WidgetLibraryTimelineProvider()) { entry in
            AlikeLibraryWidgetView(composition: entry.composition)
        }
        .configurationDisplayName(WidgetL10n.Widget.libraryDisplayName)
        .description(WidgetL10n.Widget.libraryDescription)
        // Three rows with a figure and a chevron each need the width. There is no small
        // version of this composition — a small one would be the status widget.
        .supportedFamilies([.systemMedium])
    }
}

/// Places what `WidgetPresentation.libraryComposition(for:now:)` decided.
///
/// Holds no judgement of its own — no wording, no thresholds, no routing, no premium
/// check. The extension target has no test action, so anything decided here would be
/// untestable.
struct AlikeLibraryWidgetView: View {
    let composition: WidgetLibraryComposition

    var body: some View {
        WidgetLibraryLayout(composition: composition)
            // Mandatory on iOS 17: without it the widget does not render on the
            // home screen at all.
            .containerBackground(.fill.tertiary, for: .widget)
            // The rows are `Link`s and own their own taps; this covers the header, the
            // footnote and the space around them.
            .widgetURL(composition.destination.url)
            .accessibilityLabel(composition.accessibilityLabel)
    }
}

// MARK: - Previews

private extension WidgetSnapshot {
    /// The three counts from the concept, on a subscribed account.
    static func library(now: Date = .now, isPremium: Bool = true) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now,
            photoAuthorization: .authorized,
            hasCompletedScan: true,
            lastScanDate: now,
            estimatedSavingsBytes: 1_932_735_283,
            clusterCount: 24,
            screenshotAssetCount: 86,
            blurredPhotoAssetCount: 12,
            isPremium: isPremium
        )
    }

    /// A scan that ran before the categories were counted: the rows are there, the
    /// figures are not, and neither is a fabricated zero.
    static func libraryWithUnknownCounts(now: Date = .now) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now,
            photoAuthorization: .authorized,
            hasCompletedScan: true,
            lastScanDate: now,
            clusterCount: nil,
            screenshotAssetCount: nil,
            blurredPhotoAssetCount: nil,
            isPremium: true
        )
    }
}

private func libraryEntry(_ snapshot: WidgetSnapshot?) -> WidgetLibraryEntry {
    WidgetLibraryEntry(date: .now, composition: WidgetPresentation.libraryComposition(for: snapshot))
}

// Light and dark are the same composition under a different appearance, which is the
// canvas variant selector's job. What each theme has to be checked for separately is the
// contrast of the figures, of the lock glyph and of the hero against `containerBackground`.

#Preview("Library · premium", as: .systemMedium) {
    AlikeLibraryWidget()
} timeline: {
    libraryEntry(.library())
}

#Preview("Library · locked categories", as: .systemMedium) {
    AlikeLibraryWidget()
} timeline: {
    libraryEntry(.library(isPremium: false))
}

#Preview("Library · unknown counts", as: .systemMedium) {
    AlikeLibraryWidget()
} timeline: {
    libraryEntry(.libraryWithUnknownCounts())
}

#Preview("Library · never scanned", as: .systemMedium) {
    AlikeLibraryWidget()
} timeline: {
    libraryEntry(WidgetSnapshot(generatedAt: .now, photoAuthorization: .authorized, hasCompletedScan: false))
}

#Preview("Library · no snapshot", as: .systemMedium) {
    AlikeLibraryWidget()
} timeline: {
    libraryEntry(nil)
}

#Preview("Library · stale figures", as: .systemMedium) {
    AlikeLibraryWidget()
} timeline: {
    libraryEntry(.library(now: .now.addingTimeInterval(-WidgetPresentation.staleAfter - 60)))
}
