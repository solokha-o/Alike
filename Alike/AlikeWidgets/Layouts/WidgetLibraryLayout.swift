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
/// each other and fill the height between the header and the footer.
enum WidgetLibraryMetrics {
    /// The illustration is drawn at this size and cropped to `heroPeek`, so it peeks
    /// into the header from the top-right the way the concept has it.
    static let hero: CGFloat = 56
    static let heroPeek: CGFloat = 40
    static let rowSpacing: CGFloat = 8
    static let stackSpacing: CGFloat = 6
    static let symbolWidth: CGFloat = 28
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
                Divider()
                Spacer(minLength: 0)
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(composition.rows) { row in
                        Divider()
                        // Not `widgetURL`: that is one destination for the whole widget,
                        // and the point of this composition is three.
                        Link(destination: row.destination.url) {
                            WidgetLibraryRowView(row: row)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }

                if let footnote = composition.footnote {
                    Divider()
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
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                // At accessibility sizes the three rows need every point there is, so
                // the decoration goes rather than the figures shrinking further — same
                // trade the status layouts make.
                if !dynamicTypeSize.isAccessibilitySize {
                    WidgetWordmark(style: .accent)
                }
                Text(WidgetL10n.Widget.libraryTitle)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let hero = composition.hero, !dynamicTypeSize.isAccessibilitySize {
                // The scene is taller than the header; the header's bottom edge crops it,
                // so the character leans in from the corner rather than sitting in a box.
                WidgetHeroImage(scene: hero, size: WidgetLibraryMetrics.hero)
                    .frame(height: WidgetLibraryMetrics.heroPeek, alignment: .top)
                    .clipped()
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
                .font(.title3)
                .foregroundStyle(Color.widgetAccent)
                // The elements the tinted home screen should keep bright.
                .widgetAccentable()
                .frame(width: WidgetLibraryMetrics.symbolWidth, alignment: .leading)

            Text(row.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: WidgetLibraryMetrics.rowSpacing)

            // Absent rather than "0" when the count is unknown: the snapshot's optionals
            // mean *unknown*, and a placeholder digit would read as a measured result.
            if let value = row.value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(WidgetLibraryMetrics.valueScale)
                    .lineLimit(1)
            }

            // The lock says the tap goes somewhere other than the list. It is drawn from
            // the snapshot's copy of the entitlement, which is why it never decides the
            // route: the app re-checks the live one on arrival.
            Image(systemName: row.isLocked ? "lock.fill" : "chevron.forward")
                .font(.caption.weight(.semibold))
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
