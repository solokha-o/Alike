//
//  WidgetLibraryLayout.swift
//  AlikeWidgets
//

import SwiftUI
import WidgetKit
import WidgetSupport

/// Sizes for the three-row overview.
///
/// Separate from `WidgetLayoutMetrics` on purpose: that scale exists to keep the small
/// and medium status layouts from drifting apart around one big figure, and this
/// composition has no big figure — it has three lines that have to stay legible next to
/// each other.
enum WidgetLibraryMetrics {
    static let hero: CGFloat = 38
    static let rowSpacing: CGFloat = 6
    static let stackSpacing: CGFloat = 8
    static let symbolWidth: CGFloat = 18
    /// The figures may shrink this far before they wrap. A wrapped count on one row and
    /// not on the next is what makes three rows stop reading as a list.
    static let valueScale: CGFloat = 0.7
}

/// `systemMedium`: three category lines, each its own way into its own list.
struct WidgetLibraryLayout: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let composition: WidgetLibraryComposition

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetLibraryMetrics.stackSpacing) {
            header

            if let caption = composition.caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: WidgetLibraryMetrics.rowSpacing) {
                    ForEach(composition.rows) { row in
                        // Not `widgetURL`: that is one destination for the whole widget,
                        // and the point of this composition is three.
                        Link(destination: row.destination.url) {
                            WidgetLibraryRowView(row: row)
                        }
                    }
                }

                Spacer(minLength: 0)

                if let footnote = composition.footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var header: some View {
        // At accessibility sizes the three rows need every point there is, so the
        // decoration goes rather than the figures shrinking further — same trade the
        // status layouts make.
        if let hero = composition.hero, !dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .center) {
                Text(WidgetL10n.Widget.libraryDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                WidgetHeroImage(scene: hero, size: WidgetLibraryMetrics.hero)
            }
        }
    }
}

/// One line: what it is, how many there are, and whether it is behind the paywall.
private struct WidgetLibraryRowView: View {
    let row: WidgetLibraryRow

    var body: some View {
        HStack(spacing: WidgetLibraryMetrics.rowSpacing) {
            Image(systemName: row.symbolName)
                .font(.caption)
                .foregroundStyle(Color.widgetAccent)
                // The elements the tinted home screen should keep bright.
                .widgetAccentable()
                .frame(width: WidgetLibraryMetrics.symbolWidth, alignment: .leading)

            Text(row.title)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: WidgetLibraryMetrics.rowSpacing)

            // Absent rather than "0" when the count is unknown: the snapshot's optionals
            // mean *unknown*, and a placeholder digit would read as a measured result.
            if let value = row.value {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(WidgetLibraryMetrics.valueScale)
                    .lineLimit(1)
            }

            // The lock says the tap goes somewhere other than the list. It is drawn from
            // the snapshot's copy of the entitlement, which is why it never decides the
            // route: the app re-checks the live one on arrival.
            Image(systemName: row.isLocked ? "lock.fill" : "chevron.forward")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        // One sentence per row — the category, its figure and whether it is locked —
        // rather than VoiceOver walking four separate labels inside every line.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(row.accessibilityHint)
    }
}
