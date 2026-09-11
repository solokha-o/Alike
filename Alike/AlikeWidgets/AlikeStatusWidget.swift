//
//  AlikeStatusWidget.swift
//  AlikeWidgets
//

import SwiftUI
import WidgetKit
import WidgetSupport

struct AlikeStatusWidget: Widget {
    /// Frozen once released: `WidgetCenter.reloadTimelines(ofKind:)` in the app
    /// addresses the widget by this string.
    static let kind = "AlikeStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WidgetSnapshotTimelineProvider()) { entry in
            AlikeStatusWidgetView(state: entry.state)
        }
        .configurationDisplayName(WidgetL10n.Widget.displayName)
        .description(WidgetL10n.Widget.description)
        // Additive: `systemSmall` placements already on a home screen keep the size they
        // were added at. The kind is unchanged, so the app's reload calls still address
        // this widget.
        .supportedFamilies([.systemSmall, .systemMedium])
        // The layouts carry their own `WidgetLayoutMetrics.contentMargin`: the concept
        // sits closer to the edge than WidgetKit's default margins allow.
        .contentMarginsDisabled()
    }
}

/// Places what `WidgetPresentation.composition(for:family:)` decided.
///
/// Deliberately holds no judgement of its own — no wording, no thresholds, no routing.
/// The extension target has no test action, so anything this file decided would be
/// untestable; everything it needs is resolved in `WidgetSupport` instead.
struct AlikeStatusWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily

    let state: WidgetDisplayState

    var body: some View {
        let composition = WidgetPresentation.composition(for: state, family: layoutFamily)

        Group {
            switch layoutFamily {
            case .small:
                WidgetSmallLayout(composition: composition)
            case .medium:
                WidgetMediumLayout(composition: composition)
            }
        }
        // Mandatory on iOS 17: without it the widget does not render on the
        // home screen at all.
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(composition.destination.url)
        // VoiceOver reads one sentence — the figure, what it is, when it was measured,
        // and what tapping does — rather than walking four separate labels.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(composition.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(composition.accessibilityHint)
    }

    /// `supportedFamilies` admits exactly these two, so anything else would be a family
    /// WidgetKit was never told this widget renders; the small layout is the safe
    /// reading of one if it ever arrives.
    private var layoutFamily: WidgetLayoutFamily {
        widgetFamily == .systemMedium ? .medium : .small
    }
}

// MARK: - Previews

private extension WidgetSnapshot {
    /// Suggestions waiting: concept №1, "Available to clean up".
    static func suggestions(now: Date = .now) -> WidgetSnapshot {
        .placeholder(now: now)
    }

    /// A review part-way through: concept №2, "Continue review".
    static func partialReview(now: Date = .now) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now,
            photoAuthorization: .authorized,
            hasCompletedScan: true,
            lastScanDate: now,
            estimatedSavingsBytes: 1_932_735_283,
            clusterCount: 30,
            sessionProgress: WidgetSessionProgress(
                reviewedClusters: 18,
                totalClusters: 30,
                updatedAt: now
            )
        )
    }
}

private func entry(_ snapshot: WidgetSnapshot?) -> WidgetSnapshotEntry {
    WidgetSnapshotEntry(date: .now, state: WidgetPresentation.displayState(for: snapshot))
}

// Light and dark are the same four compositions under a different appearance, which is
// the canvas variant selector's job — a duplicated `#Preview` would render identically
// and prove nothing. What each theme has to be checked for separately is the contrast of
// the figures and of the hero against `containerBackground`.

#Preview("Cleanup · small", as: .systemSmall) {
    AlikeStatusWidget()
} timeline: {
    entry(.suggestions())
}

#Preview("Cleanup · medium", as: .systemMedium) {
    AlikeStatusWidget()
} timeline: {
    entry(.suggestions())
}

#Preview("Resume · small", as: .systemSmall) {
    AlikeStatusWidget()
} timeline: {
    entry(.partialReview())
}

#Preview("Resume · medium", as: .systemMedium) {
    AlikeStatusWidget()
} timeline: {
    entry(.partialReview())
}

// The states that carry no figures, which are the ones most likely to regress into a
// fabricated zero or an empty rectangle.

#Preview("No snapshot", as: .systemSmall) {
    AlikeStatusWidget()
} timeline: {
    WidgetSnapshotEntry(date: .now, state: .unavailable)
}

#Preview("Never scanned · medium", as: .systemMedium) {
    AlikeStatusWidget()
} timeline: {
    WidgetSnapshotEntry(date: .now, state: .neverScanned)
}

#Preview("Limited photos · medium", as: .systemMedium) {
    AlikeStatusWidget()
} timeline: {
    WidgetSnapshotEntry(date: .now, state: .noAccess(.limited))
}

#Preview("All caught up · medium", as: .systemMedium) {
    AlikeStatusWidget()
} timeline: {
    WidgetSnapshotEntry(date: .now, state: .allCaughtUp(scannedAt: .now))
}

#Preview("Stale figures · medium", as: .systemMedium) {
    AlikeStatusWidget()
} timeline: {
    entry(.suggestions(now: .now.addingTimeInterval(-WidgetPresentation.staleAfter - 60)))
}
