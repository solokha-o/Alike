import SwiftUI
import Core
import DesignSystem

struct CleanupProgressCard: View {
    let progress: CleanupSessionProgress
    let onContinue: (() -> Void)?
    let onOpenHistory: () -> Void
    private let metricColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .top, spacing: Spacing.small) {
                leadingRow

                Button(action: onOpenHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .frame(width: 22, height: 22)
                }
                .cleanupGlassButton()
                .controlSize(.small)
                .accessibilityLabel(Text(CleanupL10n.Main.cleanupHistory))
            }

            ProgressView(value: progress.reviewedRatio)
            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: Spacing.small) {
                metric("\(progress.reviewedCount)/\(progress.totalClusters)", CleanupL10n.Main.reviewed)
                metric("\(progress.remainingClusters)", CleanupL10n.Main.remaining)
                metric("\(progress.totalSelectedItems)", CleanupL10n.Main.selected)
                metric(String.alikeByteCount(progress.reviewedSavingsBytes), CleanupL10n.Main.estimatedSavings)
            }
        }
        .padding(Spacing.medium)
        .cleanupGlassSurface()
    }

    @ViewBuilder
    private var leadingRow: some View {
        if let onContinue {
            Button(action: onContinue) {
                summary(
                    title: CleanupL10n.Main.continueReview,
                    subtitle: CleanupL10n.Main.pickUpWhereLeftOff,
                    iconName: "arrow.forward.circle.fill",
                    iconColor: Color.accent
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(continueAccessibilityLabel))
            .accessibilityHint(Text(CleanupL10n.Main.openNextClusterContinueCleanup))
        } else {
            summary(
                title: CleanupL10n.Main.allClustersReviewed,
                subtitle: CleanupL10n.Main.nothingLeftReviewRightNow,
                iconName: "checkmark.seal.fill",
                iconColor: .statusReviewed
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(completedAccessibilityLabel))
        }
    }

    private func summary(
        title: String,
        subtitle: String,
        iconName: String,
        iconColor: Color
    ) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.appHeadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var continueAccessibilityLabel: String {
        CleanupPresentation.continueAccessibilityLabel(progress)
    }

    private var completedAccessibilityLabel: String {
        CleanupPresentation.completedAccessibilityLabel(progress)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.caption.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Progress Card") {
    CleanupProgressCard(
        progress: CleanupSessionProgress(
            totalClusters: 10,
            reviewedCount: 4,
            needsReReviewCount: 0,
            inReviewCount: 0,
            notReviewedCount: 6,
            reviewedSavingsBytes: 2_000_000,
            totalSelectedItems: 7
        ),
        onContinue: {},
        onOpenHistory: {}
    )
    .padding()
}
