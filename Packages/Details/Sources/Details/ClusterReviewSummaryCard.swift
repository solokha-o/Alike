import SwiftUI
import Core
import DesignSystem

struct ClusterReviewSummaryCard: View {
    static let summaryContentMinimumHeight: CGFloat = 88

    enum ArtworkIdentity: Equatable, Hashable {
        case bestShot(AlikeReviewReactionCue.ID)
        case cleanupProgress(AlikeReactionCueID)
        case reaction(AlikeReactionCueID)
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
    let maximumEstimatedSavingsText: String
    let reviewStatus: ClusterReviewStatus
    let isReviewConfirmed: Bool
    let alikeReactionCue: AlikeReactionCue?
    let bestShotCelebrationCue: AlikeReviewReactionCue?
    let onBestShotCelebrationDismissed: (AlikeReviewReactionCue.ID) -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    summary
                    comparisonArtwork(width: 48)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .center, spacing: Spacing.medium) {
                    summary

                    comparisonArtwork(width: 56)
                }
            }
        }
        .padding(Spacing.small)
        .background(
            Color.secondary.opacity(ColorOpacity.placeholderFill),
            in: RoundedRectangle(cornerRadius: CornerRadius.medium)
        )
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.xSmall) {
                    assetCountLabel
                        .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: Spacing.xSmall)

                    statusLabel
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    assetCountLabel
                    statusLabel
                }
            }

            Label {
                Text(bestShotLabel)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.heroGold)
            }
            .font(.appCallout.weight(.semibold))
            .accessibilityLabel(Text("\(DetailsL10n.Common.bestShot): \(bestShotLabel)"))

            selectionSummaryLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: Self.summaryContentMinimumHeight, alignment: .leading)
        .animation(nil, value: selectedCount)
        .animation(nil, value: reviewStatus)
    }

    private var assetCountLabel: some View {
        Text(assetCountTitle)
            .font(.appHeadline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var assetCountTitle: String {
        if assetCount == 1 {
            return DetailsL10n.ClusterReviewSummaryCard.n1SimilarPhoto
        }
        return String(format: DetailsL10n.ClusterReviewSummaryCard.similarPhotos, assetCount)
    }

    private var selectionSummary: String {
        selectionSummary(
            selectedCount: selectedCount,
            estimatedSavingsText: estimatedSavingsText,
            isReviewConfirmed: isReviewConfirmed
        )
    }

    private var selectionSummaryLabel: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.reservedSelectionCounts(assetCount: assetCount), id: \.self) { count in
                // Both wordings are reserved so finishing the review never
                // reflows the card around the photo grid.
                ForEach([false, true], id: \.self) { confirmed in
                    selectionSummaryText(
                        selectionSummary(
                            selectedCount: count,
                            estimatedSavingsText: maximumEstimatedSavingsText,
                            isReviewConfirmed: confirmed
                        )
                    )
                    .hidden()
                    .accessibilityHidden(true)
                }
            }

            selectionSummaryText(selectionSummary)
                .foregroundStyle(selectedCount > 0 ? Color.accent : Color.secondary)
        }
    }

    private func selectionSummaryText(_ text: String) -> some View {
        Text(text)
            .font(.appCaption)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func selectionSummary(
        selectedCount: Int,
        estimatedSavingsText: String,
        isReviewConfirmed: Bool
    ) -> String {
        guard selectedCount > 0 else {
            return isReviewConfirmed
                ? String(format: DetailsL10n.Common.keepingAllPhotos, assetCount)
                : DetailsL10n.ClusterReviewSummaryCard.tapPhotosSelectThemCleanup
        }
        if isReviewConfirmed {
            return String(
                format: DetailsL10n.ClusterReviewSummaryCard.keepingOfEstimatedSize,
                assetCount - selectedCount,
                assetCount,
                estimatedSavingsText
            )
        }
        if selectedCount == 1 {
            return String(format: DetailsL10n.ClusterReviewSummaryCard.n1SelectedEstimatedSize, estimatedSavingsText)
        }
        return String(
            format: DetailsL10n.ClusterReviewSummaryCard.selectedEstimatedSize,
            selectedCount,
            estimatedSavingsText
        )
    }

    static func reservedSelectionCounts(assetCount: Int) -> [Int] {
        let maximumSelectedCount = max(assetCount - 1, 0)
        guard maximumSelectedCount > 0 else { return [0] }
        guard maximumSelectedCount > 1 else { return [0, 1] }
        return [0, 1, maximumSelectedCount]
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
                AlikeBestShotCelebrationView(
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
            AlikeCleanupProgressHero(
                isActive: true,
                maximumWidth: width,
                accessibilityLabel: DetailsL10n.Common.alikeOrganizingSelectedPhotos
            )
        case .reaction:
            if let alikeReactionCue {
                AlikeReactionView(cue: alikeReactionCue, maximumWidth: width)
            }
        case .comparison:
            AlikeComparisonReviewView()
                .frame(width: width)
        case .none:
            EmptyView()
        }
    }

    private var artworkIdentity: ArtworkIdentity {
        Self.resolveArtworkIdentity(
            assetCount: assetCount,
            alikeReactionCue: alikeReactionCue,
            bestShotCelebrationCue: bestShotCelebrationCue
        )
    }

    static func resolveArtworkIdentity(
        assetCount: Int,
        alikeReactionCue: AlikeReactionCue?,
        bestShotCelebrationCue: AlikeReviewReactionCue?
    ) -> ArtworkIdentity {
        if let bestShotCelebrationCue {
            return .bestShot(bestShotCelebrationCue.id)
        }
        if let alikeReactionCue {
            if AlikeComparisonReviewPresentation.isEligible(assetCount: assetCount),
               case .cleanupReady = alikeReactionCue.state {
                return .cleanupProgress(alikeReactionCue.id)
            }
            return .reaction(alikeReactionCue.id)
        }
        return AlikeComparisonReviewPresentation.isEligible(assetCount: assetCount)
            ? .comparison
            : .none
    }

    private var statusLabel: some View {
        ZStack(alignment: .leading) {
            ForEach(Self.reservedReviewStatuses, id: \.rawValue) { status in
                statusContent(
                    title: statusTitle(for: status),
                    iconName: statusIconName(for: status)
                )
                .hidden()
                .accessibilityHidden(true)
            }

            statusContent(title: statusTitle, iconName: statusIconName)
        }
        .foregroundStyle(statusColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(statusTitle))
        .accessibilityHint(Text(DetailsL10n.ClusterReviewSummaryCard.currentCleanupReviewStatus))
    }

    static let reservedReviewStatuses: [ClusterReviewStatus] = [
        .notReviewed,
        .needsReReview,
        .inReview,
        .reviewed
    ]

    private func statusContent(title: String, iconName: String) -> some View {
        HStack(spacing: Spacing.xxSmall) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .frame(width: 12, height: 12)

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusTitle: String {
        statusTitle(for: reviewStatus)
    }

    private func statusTitle(for status: ClusterReviewStatus) -> String {
        switch status {
        case .notReviewed:
            DetailsL10n.ClusterReviewSummaryCard.notReviewed
        case .needsReReview:
            DetailsL10n.ClusterReviewSummaryCard.needsReview
        case .inReview:
            DetailsL10n.ClusterReviewSummaryCard.inReview
        case .reviewed:
            DetailsL10n.Common.reviewed
        }
    }

    private var statusIconName: String {
        statusIconName(for: reviewStatus)
    }

    private func statusIconName(for status: ClusterReviewStatus) -> String {
        switch status {
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

}
