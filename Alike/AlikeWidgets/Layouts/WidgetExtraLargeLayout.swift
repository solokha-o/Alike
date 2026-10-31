//
//  WidgetExtraLargeLayout.swift
//  AlikeWidgets
//

import SwiftUI
import WidgetKit
import WidgetSupport

/// Sizes of the extra-large portrait layout (iOS 27), next to `WidgetLayoutMetrics`
/// rather than inside it: no other family reads them.
enum WidgetExtraLargeMetrics {
    /// The illustration beside the wordmark: a mark of the brand, not the widget's
    /// subject — the figures and the rows are what this size is for.
    static let hero: CGFloat = 72
    /// The hero once the rows need the height — a larger text size, a longer language.
    static let heroCompact: CGFloat = 52
    /// The figure at the default text size; `.largeTitle` is the style it scales with.
    static let headlineSize: CGFloat = 52
    static let headlineCompactSize: CGFloat = 42
    static let zoneSpacing: CGFloat = 10
    static let shareBarHeight: CGFloat = 6
    /// The group lines sit under «Similar photos», indented past its glyph.
    static let groupIndent: CGFloat = WidgetLibraryMetrics.symbolWidth + WidgetLibraryMetrics.rowSpacing
    static let groupSpacing: CGFloat = 2
}

/// `systemExtraLargePortrait`: the status, what it is a share of, and the library by
/// category — each category its own way in.
///
/// Like the other layouts it only places what `WidgetExtraLargeComposition` decided.
/// When the text size outgrows the height, the first arrangement that fits wins: the
/// hero shrinks, then goes, then group lines drop from the bottom, and the figure steps
/// down last — the number is what the widget is for.
struct WidgetExtraLargeLayout: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let composition: WidgetExtraLargeComposition

    private var base: WidgetComposition { composition.base }

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(arrangements, id: \.self) { arrangement in
                content(arrangement)
            }
        }
        .padding(WidgetLayoutMetrics.contentMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private struct Arrangement: Hashable {
        let hero: CGFloat?
        let groups: Int
        let headline: CGFloat
    }

    private var arrangements: [Arrangement] {
        let groups = composition.clusterRows.count
        let full = WidgetExtraLargeMetrics.headlineSize
        let heroes: [CGFloat?] = base.hero == nil || dynamicTypeSize.isAccessibilitySize
            ? [nil]
            : [WidgetExtraLargeMetrics.hero, WidgetExtraLargeMetrics.heroCompact, nil]
        let withGroups = heroes.map { Arrangement(hero: $0, groups: groups, headline: full) }
        let fewerGroups = stride(from: groups - 1, through: 0, by: -1).map {
            Arrangement(hero: nil, groups: $0, headline: full)
        }
        return withGroups + fewerGroups
            + [Arrangement(hero: nil, groups: 0, headline: WidgetExtraLargeMetrics.headlineCompactSize)]
    }

    private func content(_ arrangement: Arrangement) -> some View {
        VStack(alignment: .leading, spacing: WidgetExtraLargeMetrics.zoneSpacing) {
            statusZone(arrangement)

            if !composition.categoryRows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(composition.categoryRows) { row in
                        Divider()
                        // Not `widgetURL`: that is the status zone's single destination,
                        // and each category opens its own list.
                        Link(destination: row.destination.url) {
                            categoryRow(row, groups: row.category == .similar ? arrangement.groups : 0)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if let footnote = base.footnote {
                WidgetFootnote(footnote)
            }

            if let action = base.actionTitle {
                WidgetActionLabel(action, style: base.actionStyle, fullWidth: base.actionStyle == .pill)
            }
        }
    }

    /// The status — the medium composition's figure and caption — with the share bar
    /// under it, read out by VoiceOver as one sentence.
    private func statusZone(_ arrangement: Arrangement) -> some View {
        VStack(alignment: .leading, spacing: WidgetLayoutMetrics.spacing) {
            HStack(alignment: .top) {
                WidgetHeader(symbolName: base.headerSymbolName)
                Spacer(minLength: 0)
                if let hero = base.hero, let size = arrangement.hero {
                    WidgetHeroImage(scene: hero, size: size)
                }
            }

            WidgetHeadline(base.headlineParts, size: arrangement.headline, relativeTo: .largeTitle)
            WidgetCaption(base.caption, font: .title3, lines: 2)

            if let progress = base.progress {
                WidgetProgressBar(value: progress)
            }

            if let share = composition.share {
                VStack(alignment: .leading, spacing: WidgetLayoutMetrics.spacing) {
                    if share.drawsBar {
                        WidgetShareBar(fraction: share.fraction)
                    }
                    Text(share.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(WidgetLayoutMetrics.lineScale)
                }
                .padding(.top, WidgetLayoutMetrics.spacing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(composition.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(base.accessibilityHint)
    }

    private func categoryRow(_ row: WidgetLibraryRow, groups: Int) -> some View {
        VStack(alignment: .leading, spacing: WidgetExtraLargeMetrics.groupSpacing) {
            WidgetLibraryRowView(row: row)
                .padding(.vertical, WidgetLayoutMetrics.spacing)
            if groups > 0 {
                ForEach(Array(composition.clusterRows.prefix(groups).enumerated()), id: \.offset) { _, group in
                    groupLine(group)
                }
                .padding(.leading, WidgetExtraLargeMetrics.groupIndent)
                .padding(.bottom, WidgetLayoutMetrics.spacing)
            }
        }
    }

    /// Leading and trailing rather than left and right, so the line mirrors under
    /// Arabic without a branch of its own.
    private func groupLine(_ group: WidgetClusterRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.bytes)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.widgetAccent)
                .widgetAccentable()
                .lineLimit(1)
            Spacer(minLength: WidgetLayoutMetrics.spacing)
            Text(group.photos)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(WidgetLayoutMetrics.lineScale)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The reclaimable estimate as a share of the library: thinner than the review's
/// progress bar, so a widget showing both does not read as two progress figures.
private struct WidgetShareBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(Color.widgetAccent)
                    .widgetAccentable()
                    // A sliver is still drawn for a share that rounds to nothing: the bar
                    // only exists when there is something to reclaim.
                    .frame(width: max(proxy.size.height, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: WidgetExtraLargeMetrics.shareBarHeight)
        .accessibilityHidden(true)
    }
}
