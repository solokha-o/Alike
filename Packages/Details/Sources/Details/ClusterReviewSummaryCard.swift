import SwiftUI
import Core
import DesignSystem

struct ClusterReviewSummaryCard: View {
    private enum Layout {
        static let summaryContentHeight: CGFloat = 88
    }

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
            HStack(spacing: Spacing.xSmall) {
                Text(assetCountTitle)
                    .font(.appHeadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)

                Spacer(minLength: Spacing.xSmall)

                statusLabel
            }

            Label {
                Text(bestShotLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } icon: {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.heroGold)
            }
            .font(.appCallout.weight(.semibold))
            .accessibilityLabel(Text("\(appLocalized("Best Shot")): \(bestShotLabel)"))

            Text(selectionSummary)
                .font(.appCaption)
                .foregroundStyle(selectedCount > 0 ? Color.accent : Color.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(
            height: Self.summaryContentHeight(
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            ),
            alignment: .leading
        )
        .animation(nil, value: selectedCount)
        .animation(nil, value: reviewStatus)
    }

    static func summaryContentHeight(isAccessibilitySize: Bool) -> CGFloat? {
        isAccessibilitySize ? nil : Layout.summaryContentHeight
    }

    private var assetCountTitle: String {
        if assetCount == 1 {
            return appLocalized("1 Similar Photo")
        }
        return String(format: appLocalized("%d Similar Photos"), assetCount)
    }

    private var selectionSummary: String {
        guard selectedCount > 0 else {
            return appLocalized("Tap photos to select them for cleanup")
        }
        if selectedCount == 1 {
            return String(format: appLocalized("1 selected, estimated size %@."), estimatedSavingsText)
        }
        return String(
            format: appLocalized("%d selected, estimated size %@."),
            selectedCount,
            estimatedSavingsText
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
        ZStack(alignment: .leading) {
            statusContent(title: statusTitle, iconName: statusIconName)

            statusContent(title: appLocalized("Not reviewed"), iconName: "circle")
                .hidden()
            statusContent(
                title: appLocalized("Needs review"),
                iconName: "arrow.triangle.2.circlepath.circle.fill"
            )
            .hidden()
            statusContent(title: appLocalized("In review"), iconName: "clock.arrow.circlepath")
                .hidden()
            statusContent(title: appLocalized("Reviewed"), iconName: "checkmark.seal.fill")
                .hidden()
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(statusColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(statusTitle))
        .accessibilityHint(Text(appLocalized("Current cleanup review status")))
    }

    private func statusContent(title: String, iconName: String) -> some View {
        HStack(spacing: Spacing.xxSmall) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .frame(width: 12, height: 12)

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
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

}
