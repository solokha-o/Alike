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
    static let smallHero: CGFloat = 62
    /// The step down on a widget too short for the full hero — a mini's 155 pt.
    static let smallHeroCompact: CGFloat = 44
    /// The hero when it peeks over the header row's corner rather than sizing it.
    static let smallHeroPeek: CGFloat = 40
    /// How far the peeking hero reaches into the content margin, up and out.
    static let heroPeekOffset: CGFloat = 6
    /// The illustration on the medium layout: what is left of the column after the
    /// container's own padding, the capsule and its inset — the column is 138 pt on a
    /// phone, and a hero that ignores the capsule pushes the wordmark into the top edge.
    static let mediumHero: CGFloat = 108
    /// The medium hero when the capsule under it needs the height — a mini's 155 pt.
    static let mediumHeroCompact: CGFloat = 84
    /// The layouts' own margin, in place of the container's: the concept sits its
    /// content closer to the edge than WidgetKit's default, and the hero needs the room.
    static let contentMargin: CGFloat = 12
    static let spacing: CGFloat = 4
    static let mediumSpacing: CGFloat = 12
    static let progressHeight: CGFloat = 12
    /// The headline may shrink this far before it wraps or truncates. The number is the
    /// one thing on the widget that has to stay readable.
    static let headlineScale: CGFloat = 0.6
    /// How much smaller each candidate headline size is than the one before it.
    static let headlineStep: CGFloat = 2
    /// The figure's point size on each family; `.title` and `.largeTitle` are the text
    /// styles it scales with.
    static let smallHeadlineSize: CGFloat = 36
    static let mediumHeadlineSize: CGFloat = 44
    /// The figure's last step on a short widget, once everything else has given way.
    static let smallHeadlineCompactSize: CGFloat = 30
    static let mediumHeadlineCompactSize: CGFloat = 36
    static let pillHorizontalPadding: CGFloat = 14
    static let pillVerticalPadding: CGFloat = 5
    /// The capsule under the hero sits this much above the container's own padding:
    /// in the concept it floats clear of the bottom edge rather than resting on it.
    static let pillBottomInset: CGFloat = 4
    /// The caption and the detail line may shrink this far before they truncate: the
    /// column beside the hero is narrow, and «24 групи схожих фото» has to fit on one line.
    static let lineScale: CGFloat = 0.8
    /// The tint behind the action pill — the accent at a whisper, as the concept fills it.
    static let pillFillOpacity: Double = 0.18
}

/// `systemSmall`: the wordmark, one figure, what it is, and the way in.
struct WidgetSmallLayout: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let composition: WidgetComposition

    var body: some View {
        // The small widget is 155 pt on a mini and 170 on a Pro Max, and what fills the
        // one runs off both edges of the other. The first arrangement that fits wins: the
        // hero shrinks, then goes, and only then does the figure step down.
        ViewThatFits(in: .vertical) {
            ForEach(arrangements, id: \.self) { arrangement in
                content(arrangement)
            }
        }
        .padding(WidgetLayoutMetrics.contentMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private struct Arrangement: Hashable {
        enum Hero: Hashable {
            /// In the header row, which grows to its height.
            case inline(CGFloat)
            /// Over the header row's corner, into the margin: no height of its own.
            case peek(CGFloat)
            case none
        }

        let hero: Hero
        let headline: CGFloat
    }

    private var arrangements: [Arrangement] {
        let full = WidgetLayoutMetrics.smallHeadlineSize
        let compact = WidgetLayoutMetrics.smallHeadlineCompactSize
        // At accessibility sizes the text needs every point there is, so the
        // decoration goes rather than the figure shrinking further.
        guard composition.hero != nil, !dynamicTypeSize.isAccessibilitySize else {
            return [Arrangement(hero: .none, headline: full), Arrangement(hero: .none, headline: compact)]
        }
        // On a mini the text alone fills the height, so the hero stops taking a row
        // and peeks from the corner instead of leaving the widget.
        return [
            Arrangement(hero: .inline(WidgetLayoutMetrics.smallHero), headline: full),
            Arrangement(hero: .inline(WidgetLayoutMetrics.smallHeroCompact), headline: full),
            Arrangement(hero: .peek(WidgetLayoutMetrics.smallHeroPeek), headline: full),
            Arrangement(hero: .peek(WidgetLayoutMetrics.smallHeroPeek), headline: compact),
        ]
    }

    private func content(_ arrangement: Arrangement) -> some View {
        VStack(alignment: .leading, spacing: WidgetLayoutMetrics.spacing) {
            HStack(alignment: .top) {
                WidgetHeader(symbolName: composition.headerSymbolName)
                Spacer(minLength: 0)
                if let hero = composition.hero, case .inline(let size) = arrangement.hero {
                    WidgetHeroImage(scene: hero, size: size)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let hero = composition.hero, case .peek(let size) = arrangement.hero {
                    WidgetHeroImage(scene: hero, size: size)
                        .offset(x: WidgetLayoutMetrics.heroPeekOffset, y: -WidgetLayoutMetrics.heroPeekOffset)
                }
            }

            Spacer(minLength: 0)

            WidgetHeadline(composition.headlineParts, size: arrangement.headline, relativeTo: .title)
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
                // Edge to edge on small, as the concept draws it: the capsule is the
                // whole bottom row, not a chip in its corner.
                WidgetActionLabel(action, style: composition.actionStyle, fullWidth: true)
            }
        }
    }
}

/// `systemMedium`: the same figure with the room to say what it is made of, the
/// illustration filling the column beside it and the action under the illustration.
struct WidgetMediumLayout: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let composition: WidgetComposition

    var body: some View {
        HStack(alignment: .top, spacing: WidgetLayoutMetrics.mediumSpacing) {
            // 155 pt tall on a mini against 170 on a Pro Max: the column gives up the
            // caption's second line, then the detail, then a step of the figure, before
            // anything runs off an edge.
            ViewThatFits(in: .vertical) {
                textColumn(captionLines: 2, showsDetail: true, headline: WidgetLayoutMetrics.mediumHeadlineSize)
                textColumn(captionLines: 1, showsDetail: true, headline: WidgetLayoutMetrics.mediumHeadlineSize)
                textColumn(captionLines: 1, showsDetail: false, headline: WidgetLayoutMetrics.mediumHeadlineSize)
                textColumn(captionLines: 1, showsDetail: false, headline: WidgetLayoutMetrics.mediumHeadlineCompactSize)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsHero || showsPill {
                ViewThatFits(in: .vertical) {
                    heroColumn(heroSize: WidgetLayoutMetrics.mediumHero)
                    heroColumn(heroSize: WidgetLayoutMetrics.mediumHeroCompact)
                }
                // The column is the widget's full height, so the capsule lands at the
                // bottom whatever the text column beside it measures.
                .frame(maxHeight: .infinity)
            }
        }
        .padding(WidgetLayoutMetrics.contentMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func textColumn(captionLines: Int, showsDetail: Bool, headline: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: WidgetLayoutMetrics.spacing) {
            WidgetHeader(symbolName: composition.headerSymbolName)

            WidgetHeadline(composition.headlineParts, size: headline, relativeTo: .largeTitle)
            WidgetCaption(composition.caption, font: .body, lines: captionLines)

            if showsDetail, let detail = composition.detail {
                Label {
                    Text(detail.text)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(WidgetLayoutMetrics.lineScale)
                        .lineLimit(1)
                } icon: {
                    // Grey in the concept, not accent: the figure above it owns
                    // the accent, and a second accent glyph would compete with it.
                    Image(systemName: detail.symbolName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
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

            // Concept №3: the action is a line of its own under the bar, in the
            // text column. The capsule of concept №1 lives under the hero instead.
            if let action = composition.actionTitle, composition.actionStyle == .plain {
                WidgetActionLabel(action, style: .plain)
            }
        }
    }

    private func heroColumn(heroSize: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: WidgetLayoutMetrics.spacing) {
            if showsHero, let hero = composition.hero {
                WidgetHeroImage(scene: hero, size: heroSize)
            }
            Spacer(minLength: 0)
            if showsPill, let action = composition.actionTitle {
                WidgetActionLabel(action, style: .pill)
                    .padding(.bottom, WidgetLayoutMetrics.pillBottomInset)
            }
        }
    }

    private var showsHero: Bool {
        composition.hero != nil && !dynamicTypeSize.isAccessibilitySize
    }

    private var showsPill: Bool {
        composition.actionTitle != nil && composition.actionStyle == .pill
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
                .font(.subheadline.weight(.semibold))
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
    /// The concept's size at the default text size, scaled with Dynamic Type from there.
    @ScaledMetric private var size: CGFloat

    init(_ parts: WidgetHeadlineParts?, size: CGFloat, relativeTo textStyle: Font.TextStyle) {
        self.parts = parts
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    var body: some View {
        if let parts {
            // `minimumScaleFactor` does not shrink a line set in two colours — it
            // truncates «18 of 30 groups» instead — so the step-down is explicit:
            // the first size that fits on one line, down to `headlineScale`.
            // When even that is too wide («999 of 1,000 groups» in a medium column),
            // the last candidate drops the tail and lets the number take the width
            // it is offered, so nothing runs past the column into the illustration.
            ViewThatFits(in: .horizontal) {
                ForEach(candidateSizes, id: \.self) { candidate in
                    line(parts, size: candidate)
                }
                compact(parts)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .widgetAccentable()
        }
    }

    private var candidateSizes: [CGFloat] {
        let floor = (size * WidgetLayoutMetrics.headlineScale).rounded()
        return stride(from: size, through: floor, by: -WidgetLayoutMetrics.headlineStep).map { $0 }
    }

    private func line(_ parts: WidgetHeadlineParts, size: CGFloat) -> some View {
        Text(attributed(parts))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// The number alone, in one colour so `minimumScaleFactor` can shrink it into the
    /// offered width. VoiceOver still reads the whole headline.
    private func compact(_ parts: WidgetHeadlineParts) -> some View {
        Text(parts.accent)
            .font(.system(size: (size * WidgetLayoutMetrics.headlineScale).rounded(), weight: .bold, design: .rounded))
            .foregroundStyle(Color.widgetAccent)
            .lineLimit(1)
            .minimumScaleFactor(WidgetLayoutMetrics.lineScale)
            .accessibilityLabel(parts.rest.map { "\(parts.accent) \($0)" } ?? parts.accent)
    }

    private func attributed(_ parts: WidgetHeadlineParts) -> AttributedString {
        var accent = AttributedString(parts.accent)
        accent.foregroundColor = Color.widgetAccent
        guard let rest = parts.rest else { return accent }
        var tail = AttributedString(" \(rest)")
        tail.foregroundColor = .primary
        return accent + tail
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

/// What a tap leads to — a label, not a control: the widget is tappable as a whole and
/// nothing here is a button. Drawn as concept №1's capsule or concept №3's bare line,
/// whichever the composition decided.
struct WidgetActionLabel: View {
    let title: String
    let style: WidgetActionStyle
    let fullWidth: Bool

    init(_ title: String, style: WidgetActionStyle, fullWidth: Bool = false) {
        self.title = title
        self.style = style
        self.fullWidth = fullWidth
    }

    var body: some View {
        let line = HStack(spacing: WidgetLayoutMetrics.spacing) {
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.forward")
                .imageScale(.small)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(Color.widgetAccent)

        switch style {
        case .pill:
            line
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, WidgetLayoutMetrics.pillHorizontalPadding)
                .padding(.vertical, WidgetLayoutMetrics.pillVerticalPadding)
                .background(Color.widgetAccent.opacity(WidgetLayoutMetrics.pillFillOpacity), in: Capsule())
                .widgetAccentable()
        case .plain:
            line
                .widgetAccentable()
        }
    }
}

/// Reviewed groups over total groups.
///
/// Only ever drawn for a fraction the composition resolved; a session with no groups
/// yet has none, and gets no bar rather than an empty one.
private struct WidgetProgressBar: View {
    let value: Double

    var body: some View {
        // Drawn by hand rather than `ProgressView(.linear)`: that one is a 4 pt hairline
        // whatever frame it is given, and the concept's bar is a 12 pt capsule.
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.secondary)
                Capsule()
                    .fill(Color.widgetAccent)
                    .frame(width: fillWidth(in: proxy.size))
                    .widgetAccentable()
            }
            .clipShape(Capsule())
        }
        .frame(height: WidgetLayoutMetrics.progressHeight)
        // The percentage is already spelled out as "18 of 30" in the headline and
        // named in the widget's own accessibility label.
        .accessibilityHidden(true)
    }

    /// Never narrower than the bar is tall once anything is reviewed: a capsule thinner
    /// than its height pinches into a sliver — «2 of 76» is 3 pt of a 12 pt bar — where
    /// the concept draws the track's own rounded end, filled.
    private func fillWidth(in size: CGSize) -> CGFloat {
        let fraction = min(max(value, 0), 1)
        guard fraction > 0 else { return 0 }
        return min(max(size.width * fraction, size.height), size.width)
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
