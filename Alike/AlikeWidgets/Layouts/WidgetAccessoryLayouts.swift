//
//  WidgetAccessoryLayouts.swift
//  AlikeWidgets
//

import SwiftUI
import WidgetKit
import WidgetSupport

/// Sizing for the three Lock Screen slots. They are a fraction of the home screen
/// ones, so they keep their own numbers rather than bending `WidgetLayoutMetrics`.
enum WidgetAccessoryMetrics {
    /// The glyph every accessory shape is recognised by when the state brings none.
    static let brandSymbolName = "photo.stack"

    static let ringLineWidth: CGFloat = 4
    static let ringTrackOpacity: Double = 0.3
    /// Keeps the glyph and the figure inside the ring's stroke.
    static let circularContentPadding: CGFloat = 8
    static let circularSpacing: CGFloat = 0
    static let circularGlyphSize: CGFloat = 11
    static let circularFigureSize: CGFloat = 13
    static let circularFigureMinimumScale: CGFloat = 0.5
    /// «All caught up»: the tick stands where the figure would, at the figure's weight.
    static let circularStatusGlyphSize: CGFloat = 15

    static let rectangularSpacing: CGFloat = 1
    static let rectangularTitleSpacing: CGFloat = 3
    static let rectangularMinimumScale: CGFloat = 0.8
    static let rectangularSecondaryOpacity: Double = 0.75
}

// MARK: - Circular

/// A ring for "how much of it", the glyph at the top, the figure under it.
///
/// With no `progress` there is no ring at all — a 1.4.x payload has no library size, and
/// an empty ring would read as "nothing to clean".
struct WidgetCircularLayout: View {
    let composition: WidgetComposition

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            if let progress = composition.progress {
                ring(progress)
            }

            VStack(spacing: WidgetAccessoryMetrics.circularSpacing) {
                Image(systemName: topSymbolName)
                    .font(.system(size: WidgetAccessoryMetrics.circularGlyphSize, weight: .semibold))

                if let figure = composition.headlineParts {
                    figureText(figure)
                } else if let statusSymbolName {
                    Image(systemName: statusSymbolName)
                        .font(.system(size: WidgetAccessoryMetrics.circularStatusGlyphSize, weight: .bold))
                        .widgetAccentable()
                }
            }
            .padding(WidgetAccessoryMetrics.circularContentPadding)
        }
    }

    /// A state with a figure brings its own glyph; one without keeps the brand glyph on
    /// top, so the slot still says whose it is.
    private var topSymbolName: String {
        composition.headlineParts == nil
            ? WidgetAccessoryMetrics.brandSymbolName
            : composition.symbolName
    }

    /// The state's glyph in the figure's place — the tick of «all caught up», the lock of
    /// "no access". `nil` when it would only repeat the glyph above it.
    private var statusSymbolName: String? {
        composition.symbolName == WidgetAccessoryMetrics.brandSymbolName ? nil : composition.symbolName
    }

    private func figureText(_ figure: WidgetHeadlineParts) -> some View {
        (Text(figure.accent).fontWeight(.bold) + Text(figure.rest ?? ""))
            .font(.system(size: WidgetAccessoryMetrics.circularFigureSize, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(WidgetAccessoryMetrics.circularFigureMinimumScale)
            .widgetAccentable()
    }

    private func ring(_ progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(lineWidth: WidgetAccessoryMetrics.ringLineWidth)
                .opacity(WidgetAccessoryMetrics.ringTrackOpacity)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: WidgetAccessoryMetrics.ringLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(WidgetAccessoryMetrics.ringLineWidth / 2)
    }
}

// MARK: - Rectangular

/// Title, fact, action. When the slot is too short for three lines the title goes
/// first: the fact and what a tap does are what the slot is for.
struct WidgetRectangularLayout: View {
    let composition: WidgetComposition

    var body: some View {
        ViewThatFits(in: .vertical) {
            lines(showsTitle: true)
            lines(showsTitle: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lines(showsTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: WidgetAccessoryMetrics.rectangularSpacing) {
            if showsTitle {
                HStack(spacing: WidgetAccessoryMetrics.rectangularTitleSpacing) {
                    Image(systemName: composition.headerSymbolName ?? composition.symbolName)
                    Text(composition.caption)
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            }

            if let headline = composition.headline {
                Text(headline)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(WidgetAccessoryMetrics.rectangularMinimumScale)
                    .widgetAccentable()
            }

            if let progress = composition.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }

            if let footnote = composition.footnote {
                secondary(footnote)
            }

            if let actionTitle = composition.actionTitle {
                secondary(actionTitle)
            }
        }
    }

    private func secondary(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(WidgetAccessoryMetrics.rectangularMinimumScale)
            .opacity(WidgetAccessoryMetrics.rectangularSecondaryOpacity)
    }
}

// MARK: - Inline

/// One line above the clock. The system draws a single glyph and a single text, in its
/// own font, and ignores everything else.
struct WidgetInlineLayout: View {
    let composition: WidgetComposition

    var body: some View {
        Label(composition.caption, systemImage: composition.symbolName)
    }
}
