import SwiftUI
import DesignSystem

struct ClusterReviewSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let assetCount: Int
    let bestShotLabel: String
    let selectedCount: Int
    let estimatedSavingsText: String
    let reviewStatus: ClusterReviewStatus
    let bestShotCelebrationCue: ALIReviewReactionCue?
    let onBestShotCelebrationDismissed: (ALIReviewReactionCue.ID) -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    statistics
                    comparisonArtwork(width: 56)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.medium) {
                    statistics

                    comparisonArtwork(width: 72)
                }
            }
        }
        .padding(Spacing.medium)
        .background(
            Color.secondary.opacity(ColorOpacity.placeholderFill),
            in: RoundedRectangle(cornerRadius: CornerRadius.medium)
        )
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(appLocalized("Cleanup Review"))
                .font(.appHeadline)

            statusLabel

            summaryMetric(
                title: appLocalized("Best Shot"),
                value: bestShotLabel,
                usesMonospacedDigits: false
            )

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    selectionMetric
                    savingsMetric
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.medium) {
                    selectionMetric
                    savingsMetric
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionMetric: some View {
        summaryMetric(
            title: appLocalized("Selected to Review"),
            value: "\(selectedCount)",
            usesMonospacedDigits: true
        )
    }

    private var savingsMetric: some View {
        summaryMetric(
            title: appLocalized("Estimated Savings"),
            value: estimatedSavingsText,
            usesMonospacedDigits: true
        )
    }

    @ViewBuilder
    private func comparisonArtwork(width: CGFloat) -> some View {
        if let bestShotCelebrationCue {
            ALIBestShotCelebrationView(cueID: bestShotCelebrationCue.id)
                .frame(width: width)
                .onDisappear {
                    onBestShotCelebrationDismissed(bestShotCelebrationCue.id)
                }
        } else if ALIComparisonReviewPresentation.isEligible(assetCount: assetCount) {
            ALIComparisonReviewView()
                .frame(width: width)
        }
    }

    private var statusLabel: some View {
        HStack(spacing: Spacing.xxSmall) {
            Image(systemName: statusIconName)
                .font(.caption.weight(.semibold))
                .frame(width: 12, height: 12)

            Text(statusTitle)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(statusColor)
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

    private func summaryMetric(
        title: String,
        value: String,
        usesMonospacedDigits: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.appHeadline)
                .fixedSize(horizontal: false, vertical: true)
                .monospacedDigitIfNeeded(usesMonospacedDigits)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
