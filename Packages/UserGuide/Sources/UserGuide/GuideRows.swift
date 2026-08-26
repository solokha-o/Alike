import SwiftUI
import Core
import DesignSystem
import PurchasesUI

// MARK: - Tints

extension GuideLegendTint {
    var color: Color {
        switch self {
        case .needsReview:
            Color.statusNeedsReview
        case .inReview:
            Color.statusInReview
        case .reviewed:
            Color.statusReviewed
        case .isNew:
            Color.statusNew
        case .savings:
            Color.statusSavings
        }
    }
}

extension GuideItemKind {
    /// Glyph tint. The palette in `Theme.swift` is fixed RGB, so these colours are only ever used
    /// on glyphs and capsule fills — never on title or body text, where they wouldn't adapt to
    /// dark mode.
    var tint: Color {
        switch self {
        case .fact, .step, .tip, .pro:
            Color.accent
        case .caution:
            Color.red
        case .legend(let legendTint):
            legendTint.color
        }
    }
}

// MARK: - Hub row

struct GuideTopicRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var glyphColumn: CGFloat = 28

    let topic: GuideTopic

    var body: some View {
        guideRowLayout(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize) {
            Image(systemName: topic.symbol)
                .font(.title3)
                .foregroundStyle(Color.accent)
                .frame(width: glyphColumn, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(UserGuideL10n.string(topic.titleKey))
                    .font(.appHeadline)
                    .foregroundStyle(.primary)

                Text(UserGuideL10n.string(topic.summaryKey))
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Spacing.xxxSmall)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail row

struct GuideItemRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var glyphColumn: CGFloat = 28
    @ScaledMetric(relativeTo: .headline) private var stepBadgeSize: CGFloat = 32

    let item: GuideItem

    var body: some View {
        guideRowLayout(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize) {
            leading

            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                titleLine
                if let bodyKey = item.bodyKey {
                    Text(UserGuideL10n.string(bodyKey))
                        .font(.appFootnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, Spacing.xxxSmall)
        .listRowBackground(rowBackground)
        .modifier(GuideItemAccessibility(item: item))
    }

    @ViewBuilder
    private var leading: some View {
        if case .step(let number, _) = item.kind {
            Text(number.formatted(.alikeNumber))
                .font(.appHeadline)
                .foregroundStyle(Color.accent)
                .frame(minWidth: stepBadgeSize, minHeight: stepBadgeSize)
                .background(
                    Circle().fill(Color.accent.opacity(ColorOpacity.guideStepBackground))
                )
                .accessibilityHidden(true)
        } else {
            Image(systemName: item.symbol)
                .font(.title3)
                .foregroundStyle(item.kind.tint)
                .frame(width: glyphColumn, alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var titleLine: some View {
        if case .pro = item.kind {
            // Wraps instead of squeezing the title when the badge no longer fits beside it.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.xSmall) {
                    titleText
                    PremiumLockedAccessory()
                }
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    titleText
                    PremiumLockedAccessory()
                }
            }
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(UserGuideL10n.string(item.titleKey))
            .font(.appHeadline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if case .tip = item.kind {
            Color.accent.opacity(ColorOpacity.guideStepBackground)
        } else {
            Color.clear
        }
    }
}

// MARK: - Accessibility

/// Combines each row into a single VoiceOver element, and gives numbered steps a spoken position
/// so the badge is never announced as a bare digit.
private struct GuideItemAccessibility: ViewModifier {
    let item: GuideItem

    func body(content: Content) -> some View {
        if case .step(let number, let total) = item.kind {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(stepLabel(number: number, total: total)))
                .accessibilityValue(Text(item.bodyKey.map(UserGuideL10n.string) ?? ""))
        } else {
            content.accessibilityElement(children: .combine)
        }
    }

    private func stepLabel(number: Int, total: Int) -> String {
        String(
            format: UserGuideL10n.A11y.step,
            number,
            total,
            UserGuideL10n.string(item.titleKey)
        )
    }
}

// MARK: - Shared layout

/// Glyph sits beside the text normally and moves above it at accessibility text sizes, matching
/// `ScannerLibraryStatusCard`.
@ViewBuilder
func guideRowLayout<Content: View>(
    isAccessibilitySize: Bool,
    @ViewBuilder content: () -> Content
) -> some View {
    let layout = isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xSmall))
        : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.small))
    layout { content() }
}
