//
//  WidgetStatusLayouts.swift
//  AlikeWidgets
//

import SwiftUI
import WidgetKit
import WidgetSupport

/// Sizes the two layouts share, so the small and the medium cannot drift into two
/// different type scales for the same figure.
///
/// The scale is the concept's: the figure is the widget, the wordmark and the caption
/// sit around it, and the hero takes whatever column is left. Everything is a text
/// style or relative to one, so Dynamic Type still moves it.
enum WidgetLayoutMetrics {
    /// The illustration on the small layout, top-right beside the wordmark.
    static let smallHero: CGFloat = 56
    /// The illustration on the medium layout: the column height after the container's
    /// own padding, which is what "fills the right column" comes to on a phone.
    static let mediumHero: CGFloat = 120
    static let spacing: CGFloat = 4
    static let mediumSpacing: CGFloat = 12
    static let progressHeight: CGFloat = 8
    /// The headline may shrink this far before it wraps or truncates. The number is the
    /// one thing on the widget that has to stay readable.
    static let headlineScale: CGFloat = 0.6
    /// The figure's point size on each family; `.title` and `.largeTitle` are the text
    /// styles it scales with.
    static let smallHeadlineSize: CGFloat = 32
    static let mediumHeadlineSize: CGFloat = 40
    static let pillHorizontalPadding: CGFloat = 12
    static let pillVerticalPadding: CGFloat = 6
    /// The caption and the detail line may shrink this far before they truncate: the
    /// column beside the hero is narrow, and «24 групи схожих фото» has to fit on one line.
    static let lineScale: CGFloat = 0.8
    /// The tint behind the action pill — the accent at a whisper, as the concept fills it.
    static let pillFillOpacity: Double = 0.12
}

/// `systemSmall`: the wordmark, one figure, what it is, and the way in.
struct WidgetSmallLayout: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let composition: WidgetComposition

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetLayoutMetrics.spacing) {
            HStack(alignment: .top) {
                WidgetHeader(symbolName: composition.headerSymbolName)
                Spacer(minLength: 0)
                // At accessibility sizes the text needs every point there is, so the
                // decoration goes rather than the figure shrinking further.
                if let hero = composition.hero, !dynamicTypeSize.isAccessibilitySize {
                    WidgetHeroImage(scene: hero, size: WidgetLayoutMetrics.smallHero)
                }
            }

            Spacer(minLength: 0)

            WidgetHeadline(composition.headlineParts, size: WidgetLayoutMetrics.smallHeadlineSize, relativeTo: .title)
            // One line: the small widget has no height for a second, and a wrapped
            // caption is what pushed the figure up into the hero.
            WidgetCaption(composition.caption, font: .footnote, lines: 1)

            if let progress = composition.progress {
                WidgetProgressBar(value: progress)
            }

            // One trailing line, not two. The footnote only ever appears here to date a
            // stale figure, and when it does it outranks the action: the widget is
            // tappable as a whole, so naming the destination again matters less than
            // not letting an old number pass for today's.
            if let footnote = composition.footnote {
                WidgetFootnote(footnote)
            } else if let action = composition.actionTitle {
                WidgetActionLabel(action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// `systemMedium`: the same figure with the room to say what it is made of, the
/// illustration filling the column beside it and the action under the illustration.
struct WidgetMediumLayout: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let composition: WidgetComposition

    var body: some View {
        HStack(alignment: .top, spacing: WidgetLayoutMetrics.mediumSpacing) {
            VStack(alignment: .leading, spacing: WidgetLayoutMetrics.spacing) {
                WidgetHeader(symbolName: composition.headerSymbolName)

                WidgetHeadline(composition.headlineParts, size: WidgetLayoutMetrics.mediumHeadlineSize, relativeTo: .largeTitle)
                WidgetCaption(composition.caption, font: .subheadline, lines: 2)

                if let detail = composition.detail {
                    Label {
                        Text(detail.text)
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(WidgetLayoutMetrics.lineScale)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: detail.symbolName)
                            .foregroundStyle(Color.widgetAccent)
                            .widgetAccentable()
                    }
                    .font(.subheadline)
                }

                if let progress = composition.progress {
                    WidgetProgressBar(value: progress)
                }

                Spacer(minLength: 0)

                if let footnote = composition.footnote {
                    Divider()
                    WidgetFootnote(footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsHero || composition.actionTitle != nil {
                VStack(alignment: .trailing, spacing: WidgetLayoutMetrics.spacing) {
                    if showsHero, let hero = composition.hero {
                        WidgetHeroImage(scene: hero, size: WidgetLayoutMetrics.mediumHero)
                    }
                    Spacer(minLength: 0)
                    if let action = composition.actionTitle {
                        WidgetActionLabel(action)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var showsHero: Bool {
        composition.hero != nil && !dynamicTypeSize.isAccessibilitySize
    }
}

// MARK: - Pieces

/// The «Alike» wordmark, or the state's glyph for the states that have no figure to
/// carry the widget. Which one is `WidgetPresentation`'s decision, not this view's.
private struct WidgetHeader: View {
    let symbolName: String?

    var body: some View {
        if let symbolName {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(Color.widgetAccent)
                // The one element the tinted home screen should keep bright.
                .widgetAccentable()
        } else {
            WidgetWordmark(style: .primary)
        }
    }
}

/// The brand line the concept puts on every widget.
struct WidgetWordmark: View {
    enum Style {
        /// Bold, in the text colour: the status widgets.
        case primary
        /// Small, in the accent: the library widget's header, above its own title.
        case accent
    }

    let style: Style

    var body: some View {
        switch style {
        case .primary:
            Text(WidgetL10n.Widget.displayName)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        case .accent:
            Text(WidgetL10n.Widget.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.widgetAccent)
                .widgetAccentable()
                .lineLimit(1)
        }
    }
}

/// The big figure, or nothing at all.
///
/// Nothing is the honest rendering of an unknown: the states that reach this without a
/// headline have no measurement to show, and a placeholder digit would be one.
///
/// Drawn in two pieces the way the concept colours it: the number in the accent, the
/// rest — «із 30 груп» — in the text colour, on one line.
private struct WidgetHeadline: View {
    let parts: WidgetHeadlineParts?
    let size: CGFloat
    let textStyle: Font.TextStyle

    init(_ parts: WidgetHeadlineParts?, size: CGFloat, relativeTo textStyle: Font.TextStyle) {
        self.parts = parts
        self.size = size
        self.textStyle = textStyle
    }

    var body: some View {
        if let parts {
            (Text(parts.accent).foregroundStyle(Color.widgetAccent)
                + Text(parts.rest.map { " \($0)" } ?? "").foregroundStyle(.primary))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .minimumScaleFactor(WidgetLayoutMetrics.headlineScale)
                .lineLimit(1)
                .widgetAccentable()
        }
    }
}

private struct WidgetCaption: View {
    let text: String
    let font: Font
    let lines: Int

    init(_ text: String, font: Font, lines: Int) {
        self.text = text
        self.font = font
        self.lines = lines
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.secondary)
            .minimumScaleFactor(WidgetLayoutMetrics.lineScale)
            .lineLimit(lines)
    }
}

private struct WidgetFootnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}

/// What a tap leads to, drawn as the concept's capsule — a label, not a control: the
/// widget is tappable as a whole and nothing here is a button.
struct WidgetActionLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        HStack(spacing: WidgetLayoutMetrics.spacing) {
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.forward")
                .imageScale(.small)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.widgetAccent)
        .padding(.horizontal, WidgetLayoutMetrics.pillHorizontalPadding)
        .padding(.vertical, WidgetLayoutMetrics.pillVerticalPadding)
        .background(Color.widgetAccent.opacity(WidgetLayoutMetrics.pillFillOpacity), in: Capsule())
        .widgetAccentable()
    }
}

/// Reviewed groups over total groups.
///
/// Only ever drawn for a fraction the composition resolved; a session with no groups
/// yet has none, and gets no bar rather than an empty one.
private struct WidgetProgressBar: View {
    let value: Double

    var body: some View {
        ProgressView(value: value)
            .progressViewStyle(.linear)
            .tint(Color.widgetAccent)
            .widgetAccentable()
            .frame(height: WidgetLayoutMetrics.progressHeight)
            // The percentage is already spelled out as "18 of 30" in the headline and
            // named in the widget's own accessibility label.
            .accessibilityHidden(true)
    }
}

extension Color {
    /// The app's accent, mirrored into this bundle.
    ///
    /// The extension has its own bundle and cannot see the app's `AccentColor`, and it
    /// deliberately does not link `DesignSystem`, so the named color lives in
    /// `WidgetSupport`'s asset catalog. `WidgetPaletteTests` keeps the three copies
    /// from drifting apart.
    static let widgetAccent = Color("WidgetAccent", bundle: .widgetSupport)
}
