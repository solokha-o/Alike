import Cleanup
import Core
import DesignSystem
import Foundation

enum ScannerHomeAction: Equatable, Sendable {
    case startScanning
    case openCleanup
}

struct ScannerHomePresentation: Equatable, Sendable {
    enum VisualPhase: Hashable, Sendable {
        case ready
        case scanning
        case reviews
        case caughtUp
        case libraryChanged
        case error
    }

    let visualPhase: VisualPhase
    let cue: AlikeReactionCue
    let title: String
    let message: String
    let progress: Double?
    let primaryAction: ScannerHomeAction?
    let primaryActionTitle: String?
    let secondaryAction: ScannerHomeAction?
    let secondaryActionTitle: String?

    static func resolve(
        state: ScannerViewModel.State,
        hasLibraryChanged: Bool,
        hasCompletedScanBaseline: Bool,
        scanEventID: UUID
    ) -> Self {
        switch state {
        case .scanning(let progress):
            return Self(
                visualPhase: .scanning,
                cue: scanningCue(eventID: scanEventID),
                title: ScannerL10n.ScannerHome.scanningYourPhotoLibrary,
                message: ScannerL10n.ScannerHome.canSwitchTabsWhileScanning,
                progress: min(max(progress, 0), 1),
                primaryAction: nil,
                primaryActionTitle: nil,
                secondaryAction: nil,
                secondaryActionTitle: nil
            )

        case .error(let message):
            return Self(
                visualPhase: .error,
                cue: issueCue,
                title: ScannerL10n.ScannerHome.iCouldntFinishThisScan,
                message: message,
                progress: nil,
                primaryAction: .startScanning,
                primaryActionTitle: ScannerL10n.ScannerHome.retry,
                secondaryAction: hasCompletedScanBaseline ? .openCleanup : nil,
                secondaryActionTitle: hasCompletedScanBaseline
                    ? ScannerL10n.ScannerHome.reviewExistingCleanup
                    : nil
            )

        case .idle where hasLibraryChanged && hasCompletedScanBaseline,
             .completed where hasLibraryChanged && hasCompletedScanBaseline:
            return Self(
                visualPhase: .libraryChanged,
                cue: idleCue(context: .libraryChanged(newItemsCount: nil)),
                title: ScannerL10n.Alike.librarychangedMessage,
                message: ScannerL10n.Alike.librarychangedSupporting,
                progress: nil,
                primaryAction: .startScanning,
                primaryActionTitle: ScannerL10n.Alike.librarychangedCta,
                secondaryAction: .openCleanup,
                secondaryActionTitle: ScannerL10n.ScannerHome.reviewExistingCleanup
            )

        case .idle:
            return Self(
                visualPhase: .ready,
                cue: idleCue(context: .ready),
                title: ScannerL10n.Alike.readyMessage,
                message: ScannerL10n.Alike.readySupporting,
                progress: nil,
                primaryAction: .startScanning,
                primaryActionTitle: ScannerL10n.Alike.readyCta,
                secondaryAction: nil,
                secondaryActionTitle: nil
            )

        case .completed(let summary):
            let opportunityCount = summary.totalOpportunityCount
            if opportunityCount > 0 {
                return Self(
                    visualPhase: .reviews,
                    cue: idleCue(context: .hasReviews(count: opportunityCount)),
                    title: ScannerL10n.ScannerHome.cleanupOpportunitiesAreReady,
                    message: ScannerL10n.ScannerHome.reviewEachSuggestionBeforeAnything,
                    progress: nil,
                    primaryAction: .openCleanup,
                    primaryActionTitle: ScannerL10n.ScannerHome.reviewCleanup,
                    secondaryAction: .startScanning,
                    secondaryActionTitle: ScannerL10n.ScannerHome.scanAgain
                )
            }

            return Self(
                visualPhase: .caughtUp,
                cue: idleCue(context: .allCaughtUp),
                title: ScannerL10n.ScannerHome.libraryUpDate,
                message: ScannerL10n.ScannerHome.noCleanupOpportunitiesWereFound,
                progress: nil,
                primaryAction: .startScanning,
                primaryActionTitle: ScannerL10n.ScannerHome.scanAgain,
                secondaryAction: nil,
                secondaryActionTitle: nil
            )
        }
    }

    private static func scanningCue(eventID: UUID) -> AlikeReactionCue {
        AlikeReactionCue(
            id: AlikeReactionCueID(
                eventID: .scan(eventID),
                kind: .scanning
            ),
            state: .scanning,
            persistence: .persistent
        )
    }

    private static let issueCue = AlikeReactionCue(
        id: AlikeReactionCueID(
            eventID: .operation(UUID(uuidString: "15CD3DE5-39D9-46BB-9DB0-232139801BC6")!),
            kind: .recoverableError
        ),
        state: .recoverableError(AlikeErrorContext(operation: .scan)),
        persistence: .persistent
    )

    private static func idleCue(context: AlikeIdleContext) -> AlikeReactionCue {
        AlikeReactionCue(
            id: AlikeReactionCueID(eventID: .idle, kind: .idle),
            state: .idle(context),
            persistence: .persistent
        )
    }
}

struct ScannerAllowancePresentation: Equatable, Sendable {
    let remainingScans: Int
    let totalScans: Int

    static func resolve(
        hasUnlimitedAccess: Bool,
        remainingScans: Int,
        totalScans: Int
    ) -> Self? {
        guard !hasUnlimitedAccess else { return nil }
        return Self(
            remainingScans: max(0, remainingScans),
            totalScans: max(0, totalScans)
        )
    }
}

extension ScanSummary {
    var totalOpportunityCount: Int {
        max(0, clusterCount) + max(0, cleanupCategoryCandidateCount)
    }
}
