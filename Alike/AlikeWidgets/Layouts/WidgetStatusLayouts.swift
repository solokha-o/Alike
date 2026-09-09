//
//  WidgetStatusLayouts.swift
//  AlikeWidgets
//

import SwiftUI
import WidgetKit
import WidgetSupport

/// Sizes the two layouts share, so the small and the medium cannot drift into two
/// different type scales for the same figure.
enum WidgetLayoutMetrics {
    static let smallHero: CGFloat = 46
    static let mediumHero: CGFloat = 84
    static let spacing: CGFloat = 4
    static let mediumSpacing: CGFloat = 12
    static let progressHeight: CGFloat = 6
    /// The headline may shrink this far before it wraps or truncates. The number is the
    /// one thing on the widget that has to stay readable.
    static let headlineScale: CGFloat = 0.6
}

/// `systemSmall`: one figure, what it is, and one line of context.
struct WidgetSmallLayout: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let composition: WidgetComposition

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetLayoutMetrics.spacing) {
            HStack(alignment: .top) {
                Image(systemName: composition.symbolName)
                    .font(.title3)
                    .foregroundStyle(Color.widgetAccent)
                    // The one element the tinted home screen should keep bright.
                    .widgetAccentable()
                Spacer(minLength: 0)
                // At accessibility sizes the text needs every point there is, so the
                // decoration goes rather than the figure shrinking further.
                if let hero = composition.hero, !dynamicTypeSize.isAccessibilitySize {
                    WidgetHeroImage(scene: hero, size: WidgetLayoutMetrics.smallHero)
                }
            }

            Spacer(minLength: 0)

            WidgetHeadline(composition.headline)
            WidgetCaption(composition.caption)

            if let progress = composition.progress {
                WidgetProgressBar(value: progress)
            }

            if let footnote = composition.footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `systemMedium`: the same figure with the room to say what it is made of, plus the
/// illustration beside it.
struct WidgetMediumLayout: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let composition: WidgetComposition

    var body: some View {
        HStack(alignment: .center, spacing: WidgetLayoutMetrics.mediumSpacing) {
            VStack(alignment: .leading, spacing: WidgetLayoutMetrics.spacing) {
                Label {
                    Text(composition.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } icon: {
                    Image(systemName: composition.symbolName)
                        .foregroundStyle(Color.widgetAccent)
                        .widgetAccentable()
                }
                .font(.caption)

                WidgetHeadline(composition.headline)

                if let progress = composition.progress {
                    WidgetProgressBar(value: progress)
                }

                if let footnote = composition.footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                if let action = composition.actionTitle {
                    Spacer(minLength: 0)
                    Text(action)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.widgetAccent)
                        .widgetAccentable()
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let hero = composition.hero, !dynamicTypeSize.isAccessibilitySize {
                WidgetHeroImage(scene: hero, size: WidgetLayoutMetrics.mediumHero)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The big figure, or nothing at all.
///
/// Nothing is the honest rendering of an unknown: the states that reach this without a
/// headline have no measurement to show, and a placeholder digit would be one.
private struct WidgetHeadline: View {
    let text: String?

    init(_ text: String?) { self.text = text }

    var body: some View {
        if let text {
            Text(text)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .minimumScaleFactor(WidgetLayoutMetrics.headlineScale)
                .lineLimit(1)
        }
    }
}

private struct WidgetCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
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
            // The percentage is already spelled out as "18/30" in the headline and
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
