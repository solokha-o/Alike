import Cleanup
import Core
import DesignSystem
import Foundation

enum ScannerHomeAction: Equatable, Sendable {
    case startScanning
    case openCleanup
}

struct ScannerHomePresentation: Equatable, Sendable {
    let cue: ALIReactionCue
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
        hasCompletedScanBaseline: Bool
    ) -> Self {
        switch state {
        case .scanning(let progress):
            return Self(
                cue: scanningCue,
                title: appLocalized("Scanning your photo library"),
                message: appLocalized("You can switch tabs while scanning. Your cleanup results will refresh when it finishes."),
                progress: min(max(progress, 0), 1),
                primaryAction: nil,
                primaryActionTitle: nil,
                secondaryAction: nil,
                secondaryActionTitle: nil
            )

        case .error(let message):
            return Self(
                cue: issueCue,
                title: appLocalized("I couldn't finish this scan."),
                message: message,
                progress: nil,
                primaryAction: .startScanning,
                primaryActionTitle: appLocalized("Retry"),
                secondaryAction: hasCompletedScanBaseline ? .openCleanup : nil,
                secondaryActionTitle: hasCompletedScanBaseline
                    ? appLocalized("Review Existing Cleanup")
                    : nil
            )

        case .idle where hasLibraryChanged && hasCompletedScanBaseline,
             .completed where hasLibraryChanged && hasCompletedScanBaseline:
            return Self(
                cue: idleCue(context: .libraryChanged(newItemsCount: nil)),
                title: appLocalized("scanner.ali.libraryChanged.message"),
                message: appLocalized("scanner.ali.libraryChanged.supporting"),
                progress: nil,
                primaryAction: .startScanning,
                primaryActionTitle: appLocalized("scanner.ali.libraryChanged.cta"),
                secondaryAction: .openCleanup,
                secondaryActionTitle: appLocalized("Review Existing Cleanup")
            )

        case .idle:
            return Self(
                cue: idleCue(context: .ready),
                title: appLocalized("scanner.ali.ready.message"),
                message: appLocalized("scanner.ali.ready.supporting"),
                progress: nil,
                primaryAction: .startScanning,
                primaryActionTitle: appLocalized("scanner.ali.ready.cta"),
                secondaryAction: nil,
                secondaryActionTitle: nil
            )

        case .completed(let summary):
            let opportunityCount = summary.totalOpportunityCount
            if opportunityCount > 0 {
                return Self(
                    cue: idleCue(context: .hasReviews(count: opportunityCount)),
                    title: appLocalized("Cleanup opportunities are ready"),
                    message: appLocalized("Review each suggestion before anything is removed."),
                    progress: nil,
                    primaryAction: .openCleanup,
                    primaryActionTitle: appLocalized("Review Cleanup"),
                    secondaryAction: .startScanning,
                    secondaryActionTitle: appLocalized("Scan Again")
                )
            }

            return Self(
                cue: idleCue(context: .allCaughtUp),
                title: appLocalized("Your library is up to date"),
                message: appLocalized("No cleanup opportunities were found in this scan."),
                progress: nil,
                primaryAction: .startScanning,
                primaryActionTitle: appLocalized("Scan Again"),
                secondaryAction: nil,
                secondaryActionTitle: nil
            )
        }
    }

    private static let scanningCue = ALIReactionCue(
        id: ALIReactionCueID(
            eventID: .operation(UUID(uuidString: "7FDF377A-F575-45D2-BEC5-E56C99323571")!),
            kind: .scanning
        ),
        state: .scanning,
        persistence: .persistent
    )

    private static let issueCue = ALIReactionCue(
        id: ALIReactionCueID(
            eventID: .operation(UUID(uuidString: "15CD3DE5-39D9-46BB-9DB0-232139801BC6")!),
            kind: .recoverableError
        ),
        state: .recoverableError(ALIErrorContext(operation: .scan)),
        persistence: .persistent
    )

    private static func idleCue(context: ALIIdleContext) -> ALIReactionCue {
        ALIReactionCue(
            id: ALIReactionCueID(eventID: .idle, kind: .idle),
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
