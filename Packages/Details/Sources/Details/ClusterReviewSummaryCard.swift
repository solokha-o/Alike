import SwiftUI
import Core
import DesignSystem

struct ClusterReviewSummaryCard: View {
    static let summaryContentMinimumHeight: CGFloat = 88
    /// Longer than any real reason line, since it strings every code
    /// together. Used only to reserve height, never shown, so the reason
    /// line appearing or disappearing cannot change the card's size.
    static let reservedBestShotReasonText = BestShotReasonSummary.text(for: BestShotReasonCode.allCases) ?? ""

    enum ArtworkIdentity: Equatable, Hashable {
        case bestShot(AlikeReviewReactionCue.ID)
        case cleanupProgress(AlikeReactionCueID)
        case reaction(AlikeReactionCueID)
        case comparison
        case none
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Latches once the foreign-edit note has been shown, so the height it
    /// takes stays reserved after the note itself goes away.
    @State private var hasShownForeignEditNote = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let assetCount: Int
    let bestShotLabel: String
    let bestShotConfidence: BestShotConfidence
    var isChoosingBestShot = false
    let bestShotReasonCodes: [BestShotReasonCode]
    var isBestShotEditedElsewhere = false
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

            bestShotSummary

            selectionSummaryLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: Self.summaryContentMinimumHeight, alignment: .leading)
        .animation(nil, value: selectedCount)
        .animation(nil, value: reviewStatus)
    }

    /// The visible state sits over a hidden reservation of the tallest
    /// layout the resolved state can produce, so choosing between the three
    /// states below — or the resolved state gaining or losing its reason
    /// line or foreign-edit note — never changes the card's height.
    private var bestShotSummary: some View {
        ZStack(alignment: .topLeading) {
            bestShotSummaryReservation
                .hidden()
                .accessibilityHidden(true)

            bestShotSummaryContent
        }
        .onAppear { hasShownForeignEditNote = isBestShotEditedElsewhere }
        .onChange(of: isBestShotEditedElsewhere) { _, isEditedElsewhere in
            if isEditedElsewhere { hasShownForeignEditNote = true }
        }
    }

    /// Title, reason line and — only where it applies — the foreign-edit note,
    /// all present at once, in the same fonts as the real content. Never shown:
    /// `.hidden()` keeps it out of the accessibility tree while still
    /// contributing its size to the enclosing `ZStack`.
    ///
    /// The note's slot is latched rather than mirrored: it disappears from the
    /// real content once the photo carries Alike's own edit, and a cluster that
    /// never had a foreign edit should not pay a line of height for one.
    private var bestShotSummaryReservation: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Label {
                Text(bestShotTitle)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: bestShotConfidence.badgeSymbolName)
            }
            .font(.appCallout.weight(.semibold))

            Text(Self.reservedBestShotReasonText)
                .font(.appCaption)
                .fixedSize(horizontal: false, vertical: true)

            if hasShownForeignEditNote {
                Label {
                    Text(DetailsL10n.ClusterDetails.editedInAnotherAppNote)
                } icon: {
                    Image(systemName: "square.and.pencil")
                }
                .font(.appCaption)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Three states in one place: a confident pick, a hedged one, and the
    /// honest "nothing stands out here, you choose".
    @ViewBuilder
    private var bestShotSummaryContent: some View {
        Group {
            if isChoosingBestShot {
                // Says what is happening instead of showing a pick that is about to
                // change under the user's eyes.
                Label {
                    Text(DetailsL10n.ClusterDetails.choosingBestShot)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    ProgressView()
                        .controlSize(.small)
                }
                .font(.appCallout.weight(.semibold))
                .foregroundStyle(.secondary)
                .transition(.opacity)
            } else if bestShotConfidence == .unresolved {
                Label {
                    Text(DetailsL10n.ClusterDetails.noObviousBestShot)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: bestShotConfidence.badgeSymbolName)
                        .foregroundStyle(.secondary)
                }
                .font(.appCallout.weight(.semibold))
                .foregroundStyle(.secondary)
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Label {
                        Text(bestShotTitle)
                            .contentTransition(.opacity)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: bestShotConfidence.badgeSymbolName)
                            .foregroundStyle(Color.heroGold)
                    }
                    .font(.appCallout.weight(.semibold))

                    if let reasons = BestShotReasonSummary.text(for: bestShotReasonCodes) {
                        Text(reasons)
                            .font(.appCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }

                    if isBestShotEditedElsewhere {
                        // Says where the photo's current look came from, so
                        // enhancing it is never a surprise.
                        Label {
                            Text(DetailsL10n.ClusterDetails.editedInAnotherAppNote)
                        } icon: {
                            Image(systemName: "square.and.pencil")
                        }
                        .font(.appCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: bestShotAccessibilityLabel))
                .transition(.opacity)
            }
        }
        // A crossfade, not a pop, whichever of the three states changes: the
        // choosing state settling into a pick, the reason line landing once
        // scoring completes, or the foreign-edit note appearing.
        .animation(reduceMotion ? nil : .appSmooth, value: isChoosingBestShot)
        .animation(reduceMotion ? nil : .appSmooth, value: bestShotConfidence)
        .animation(reduceMotion ? nil : .appSmooth, value: bestShotReasonCodes)
        .animation(reduceMotion ? nil : .appSmooth, value: isBestShotEditedElsewhere)
    }

    private var bestShotTitle: String {
        bestShotConfidence == .lowConfidence
            ? "\(bestShotConfidence.badgeTitle): \(bestShotLabel)"
            : bestShotLabel
    }

    private var bestShotAccessibilityLabel: String {
        var spoken = "\(bestShotConfidence.badgeTitle): \(bestShotLabel)"
        if let reasons = BestShotReasonSummary.text(for: bestShotReasonCodes) {
            spoken += ". \(reasons)"
        }
        // The explicit label replaces the spoken content of the combined
        // children, so the warning has to be repeated here or VoiceOver users
        // never hear that enhancing would replace another app's edit.
        if isBestShotEditedElsewhere {
            spoken += ". \(DetailsL10n.ClusterDetails.editedInAnotherAppNote)"
        }
        return spoken
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
        return DetailsL10n.ClusterReviewSummaryCard.selectionSummary(
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
