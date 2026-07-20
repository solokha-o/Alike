import SwiftUI
import Core
import DesignSystem

struct ClusterReviewSummaryCard: View {
    enum ArtworkIdentity: Equatable, Hashable {
        case bestShot(ALIReviewReactionCue.ID)
        case cleanupProgress(ALIReactionCueID)
        case reaction(ALIReactionCueID)
        case comparison
        case none
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let assetCount: Int
    let bestShotLabel: String
    let selectedCount: Int
    let estimatedSavingsText: String
    let reviewStatus: ClusterReviewStatus
    let aliReactionCue: ALIReactionCue?
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

    private func comparisonArtwork(width: CGFloat) -> some View {
        ZStack {
            artwork(for: artworkIdentity, width: width)
                .id(artworkIdentity)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.84).combined(with: .opacity),
                        removal: .scale(scale: 1.06).combined(with: .opacity)
                    )
                )
        }
        .frame(width: width, height: width)
        .animation(reduceMotion ? nil : .appSmooth, value: artworkIdentity)
    }

    @ViewBuilder
    private func artwork(for identity: ArtworkIdentity, width: CGFloat) -> some View {
        switch identity {
        case .bestShot:
            if let bestShotCelebrationCue {
                ALIBestShotCelebrationView(
                    cueID: bestShotCelebrationCue.id,
                    onPlaybackFinished: {
                        onBestShotCelebrationDismissed(bestShotCelebrationCue.id)
                    }
                )
                    .frame(width: width)
                    .onDisappear {
                        onBestShotCelebrationDismissed(bestShotCelebrationCue.id)
                    }
            }
        case .cleanupProgress:
            ALICleanupProgressHero(
                isActive: true,
                maximumWidth: width,
                accessibilityLabel: appLocalized("ALI organizing selected photos")
            )
        case .reaction:
            if let aliReactionCue {
                ALIReactionView(cue: aliReactionCue, maximumWidth: width)
            }
        case .comparison:
            ALIComparisonReviewView()
                .frame(width: width)
        case .none:
            EmptyView()
        }
    }

    private var artworkIdentity: ArtworkIdentity {
        Self.resolveArtworkIdentity(
            assetCount: assetCount,
            aliReactionCue: aliReactionCue,
            bestShotCelebrationCue: bestShotCelebrationCue
        )
    }

    static func resolveArtworkIdentity(
        assetCount: Int,
        aliReactionCue: ALIReactionCue?,
        bestShotCelebrationCue: ALIReviewReactionCue?
    ) -> ArtworkIdentity {
        if let bestShotCelebrationCue {
            return .bestShot(bestShotCelebrationCue.id)
        }
        if let aliReactionCue {
            if ALIComparisonReviewPresentation.isEligible(assetCount: assetCount),
               case .cleanupReady = aliReactionCue.state {
                return .cleanupProgress(aliReactionCue.id)
            }
            return .reaction(aliReactionCue.id)
        }
        return ALIComparisonReviewPresentation.isEligible(assetCount: assetCount)
            ? .comparison
            : .none
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
