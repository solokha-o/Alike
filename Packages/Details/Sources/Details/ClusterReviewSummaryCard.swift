import SwiftUI
import DesignSystem

struct ClusterReviewSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let bestShotLabel: String
    let selectedCount: Int
    let estimatedSavingsText: String
    let reviewStatus: ClusterReviewStatus

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .center, spacing: Spacing.small) {
                Image(systemName: statusIconName)
                    .font(.appHeadline)
                    .foregroundStyle(statusColor)
                    .frame(width: 20, height: 20)

                Text(appLocalized("Cleanup Review"))
                    .font(.appHeadline)
                    .lineLimit(1)

                Spacer()

                statusChip
            }
            .frame(minHeight: 28)

            summaryMetric(
                title: appLocalized("Best Shot"),
                value: bestShotLabel,
                lineLimit: 2,
                minHeight: 56
            )

            HStack(alignment: .top, spacing: Spacing.medium) {
                summaryMetric(
                    title: appLocalized("Selected to Review"),
                    value: "\(selectedCount)",
                    usesMonospacedDigits: true,
                    minHeight: 44
                )
                summaryMetric(
                    title: appLocalized("Estimated Savings"),
                    value: estimatedSavingsText,
                    usesMonospacedDigits: true,
                    minHeight: 44
                )
            }
        }
        .padding(Spacing.medium)
        .background(Color.secondaryBackground, in: RoundedRectangle(cornerRadius: CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(statusColor.opacity(borderOpacity), lineWidth: 1)
        )
        .subtleShadow()
    }

    private var statusChip: some View {
        HStack(spacing: Spacing.xxSmall) {
            Image(systemName: statusIconName)
                .font(.caption.weight(.semibold))
                .frame(width: 12, height: 12)

            Text(statusTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, Spacing.xSmall)
        .padding(.vertical, 6)
        .frame(minWidth: 110, minHeight: 28, alignment: .center)
        .background(statusColor.opacity(chipOpacity), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(statusTitle))
        .accessibilityHint(Text(appLocalized("Current cleanup review status")))
    }

    private var statusTitle: String {
        switch reviewStatus {
        case .notReviewed:
            appLocalized("Not reviewed")
        case .needsReReview:
            appLocalized("Needs review")
        case .inReview:
            appLocalized("In review")
        case .reviewed:
            appLocalized("Reviewed")
        }
    }

    private var statusIconName: String {
        switch reviewStatus {
        case .notReviewed:
            "circle"
        case .needsReReview:
            "arrow.triangle.2.circlepath.circle.fill"
        case .inReview:
            "clock.arrow.circlepath"
        case .reviewed:
            "checkmark.seal.fill"
        }
    }

    private var statusColor: Color {
        switch reviewStatus {
        case .notReviewed:
            colorScheme == .dark ? .primary.opacity(0.85) : .secondary
        case .needsReReview:
            .statusNeedsReview
        case .inReview:
            .statusInReview
        case .reviewed:
            .statusReviewed
        }
    }

    private var chipOpacity: Double {
        colorScheme == .dark ? ColorOpacity.statusBackgroundDark : ColorOpacity.statusBackground
    }

    private var borderOpacity: Double {
        colorScheme == .dark ? ColorOpacity.cardBorderDark : ColorOpacity.cardBorder
    }

    private func summaryMetric(
        title: String,
        value: String,
        usesMonospacedDigits: Bool = false,
        lineLimit: Int = 1,
        minHeight: CGFloat = 44
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.appHeadline)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .minimumScaleFactor(0.7)
                .monospacedDigitIfNeeded(usesMonospacedDigits)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
    }
}

private extension View {
    @ViewBuilder
    func monospacedDigitIfNeeded(_ enabled: Bool) -> some View {
        if enabled {
            self.monospacedDigit()
        } else {
            self
        }
    }
}
