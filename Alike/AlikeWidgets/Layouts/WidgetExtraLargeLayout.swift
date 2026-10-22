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
    /// The illustration in the header row, beside the wordmark.
    static let hero: CGFloat = 132
    /// The hero once the rows need the height — a larger text size, a longer language.
    static let heroCompact: CGFloat = 96
    /// The figure at the default text size; `.largeTitle` is the style it scales with.
    static let headlineSize: CGFloat = 60
    static let headlineCompactSize: CGFloat = 48
    static let spacing: CGFloat = 12
    static let rowSpacing: CGFloat = 8
}

/// `systemExtraLargePortrait`: the medium widget's story with the room to list the
/// largest groups under it.
///
/// Like the other layouts it only places what `WidgetExtraLargeComposition` decided.
/// When the text size outgrows the height, the first arrangement that fits wins: the
/// hero shrinks, then goes, then rows drop from the bottom, and the figure steps down
/// last — the number is what the widget is for.
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
        let rows: Int
        let headline: CGFloat
    }

    private var arrangements: [Arrangement] {
        let rows = composition.clusterRows.count
        let full = WidgetExtraLargeMetrics.headlineSize
        let compact = WidgetExtraLargeMetrics.headlineCompactSize
        let heroes: [CGFloat?] = base.hero == nil || dynamicTypeSize.isAccessibilitySize
            ? [nil]
            : [WidgetExtraLargeMetrics.hero, WidgetExtraLargeMetrics.heroCompact, nil]
        let withRows = heroes.map { Arrangement(hero: $0, rows: rows, headline: full) }
        let fewerRows = stride(from: rows - 1, through: 0, by: -1).map {
            Arrangement(hero: nil, rows: $0, headline: full)
        }
        return withRows + fewerRows + [Arrangement(hero: nil, rows: 0, headline: compact)]
    }

    private func content(_ arrangement: Arrangement) -> some View {
        VStack(alignment: .leading, spacing: WidgetExtraLargeMetrics.spacing) {
            HStack(alignment: .top) {
                WidgetHeader(symbolName: base.headerSymbolName)
                Spacer(minLength: 0)
                if let hero = base.hero, let size = arrangement.hero {
                    WidgetHeroImage(scene: hero, size: size)
                }
            }

            VStack(alignment: .leading, spacing: WidgetLayoutMetrics.spacing) {
                WidgetHeadline(base.headlineParts, size: arrangement.headline, relativeTo: .largeTitle)
                WidgetCaption(base.caption, font: .title3, lines: 2)

                if let countLine = composition.clusterCountLine {
                    Label {
                        Text(countLine)
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(WidgetLayoutMetrics.lineScale)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "photo.stack")
                            .foregroundStyle(.secondary)
                    }
                    .font(.body)
                }

                if let progress = base.progress {
                    WidgetProgressBar(value: progress)
                }
            }

            if arrangement.rows > 0, let title = composition.rowsTitle {
                Divider()
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(WidgetLayoutMetrics.lineScale)
                VStack(spacing: WidgetExtraLargeMetrics.rowSpacing) {
                    ForEach(Array(composition.clusterRows.prefix(arrangement.rows).enumerated()), id: \.offset) { _, row in
                        clusterRow(row)
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

    /// Leading and trailing rather than left and right, so the row mirrors under
    /// Arabic without a branch of its own.
    private func clusterRow(_ row: WidgetClusterRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "square.stack")
                .foregroundStyle(.secondary)
            Text(row.bytes)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.widgetAccent)
                .widgetAccentable()
                .lineLimit(1)
            Spacer(minLength: WidgetLayoutMetrics.spacing)
            Text(row.photos)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(WidgetLayoutMetrics.lineScale)
        }
    }
}
