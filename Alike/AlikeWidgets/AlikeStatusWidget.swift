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
        .supportedFamilies([.systemSmall])
    }
}

struct AlikeStatusWidgetView: View {
    let state: WidgetDisplayState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(Color.widgetAccent)
            Spacer(minLength: 0)
            if let headline {
                Text(headline)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Mandatory on iOS 17: without it the widget does not render on the
        // home screen at all.
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WidgetPresentation.destination(for: state).url)
        // VoiceOver reads one sentence — the figure, what it is, when it was measured,
        // and what tapping does — rather than walking four separate labels.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(WidgetL10n.Accessibility.openCleanup)
    }

    private var symbolName: String {
        switch state {
        case .unavailable, .noAccess: "lock.fill"
        case .neverScanned: "viewfinder"
        case .allCaughtUp: "checkmark.circle.fill"
        case .libraryChanged: "arrow.triangle.2.circlepath"
        case .resumeReview: "rectangle.on.rectangle"
        case .hasSuggestions: "photo.stack"
        }
    }

    /// The big number, when there is an honest one to show.
    private var headline: String? {
        switch state {
        case let .hasSuggestions(bytes, _, _, _), let .libraryChanged(bytes, _):
            bytes.map { WidgetFormatting.byteCount($0) }
        case let .resumeReview(progress, _):
            "\(WidgetFormatting.number(progress.reviewedClusters))/\(WidgetFormatting.number(progress.totalClusters))"
        case .unavailable, .noAccess, .neverScanned, .allCaughtUp:
            nil
        }
    }

    private var caption: String {
        switch state {
        case .unavailable:
            WidgetL10n.Status.openApp
        case let .noAccess(status):
            status == .limited ? WidgetL10n.Status.limitedAccess : WidgetL10n.Status.noAccess
        case .neverScanned:
            WidgetL10n.Status.scanPrompt
        case .allCaughtUp:
            WidgetL10n.Status.allCaughtUp
        case .libraryChanged:
            WidgetL10n.Status.libraryChanged
        case .resumeReview:
            WidgetL10n.Status.continueReview
        case .hasSuggestions:
            WidgetL10n.Status.reclaimable
        }
    }

    /// The timestamp that keeps stale figures from being read as current, plus the
    /// group count when the numbers are fresh.
    private var footnote: String? {
        switch state {
        case let .hasSuggestions(_, clusterCount, scannedAt, isStale):
            if isStale, let scannedAt {
                WidgetL10n.Status.lastScanned(WidgetFormatting.timestamp(scannedAt, timeStyle: .omitted))
            } else {
                clusterCount.map { WidgetL10n.Status.groups($0) }
            }
        case let .libraryChanged(_, scannedAt):
            scannedAt.map { WidgetL10n.Status.lastScanned(WidgetFormatting.timestamp($0, timeStyle: .omitted)) }
        case let .allCaughtUp(scannedAt):
            scannedAt.map { WidgetL10n.Status.lastScanned(WidgetFormatting.timestamp($0, timeStyle: .omitted)) }
        case let .resumeReview(progress, _):
            WidgetL10n.Status.groups(progress.remainingClusters)
        case .unavailable, .noAccess, .neverScanned:
            nil
        }
    }

    /// Includes the footnote: it carries the scan date on a stale reading, and dropping
    /// it left VoiceOver presenting an old figure as the current one.
    private var accessibilityLabel: String {
        [headline, caption, footnote].compactMap { $0 }.joined(separator: ", ")
    }
}

private extension Color {
    /// The app's accent, mirrored into this bundle.
    ///
    /// The extension has its own bundle and cannot see the app's `AccentColor`, and it
    /// deliberately does not link `DesignSystem`, so the named color lives in
    /// `WidgetSupport`'s asset catalog. `WidgetPaletteTests` keeps the three copies
    /// from drifting apart.
    static let widgetAccent = Color("WidgetAccent", bundle: .widgetSupport)
}

#Preview("Suggestions", as: .systemSmall) {
    AlikeStatusWidget()
} timeline: {
    WidgetSnapshotEntry(date: .now, state: WidgetPresentation.displayState(for: .placeholder()))
}

#Preview("No snapshot", as: .systemSmall) {
    AlikeStatusWidget()
} timeline: {
    WidgetSnapshotEntry(date: .now, state: .unavailable)
}
