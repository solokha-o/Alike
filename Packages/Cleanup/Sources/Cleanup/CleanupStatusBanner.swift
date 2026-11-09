import CleanupWorkspace
import Core
import DesignSystem
import SwiftUI

struct CleanupStatusBanner: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var showsProgress = false
    var progress: Double?
    var dismiss: (() -> Void)?

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLayout
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalLayout
                    stackedLayout
                }
            }
        }
        .padding(Spacing.medium)
        .alikeGlassSurface()
    }

    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            indicator
            statusText(allowsWrapping: false)
            Spacer(minLength: Spacing.small)
            compactAction
            dismissButton
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .top, spacing: Spacing.small) {
                indicator
                statusText(allowsWrapping: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                dismissButton
            }

            expandedAction
        }
    }

    @ViewBuilder
    private var indicator: some View {
        if showsProgress {
            ProgressView(value: progress)
                .frame(width: 22)
        } else {
            Image(systemName: icon)
                .foregroundStyle(Color.accent)
        }
    }

    private func statusText(allowsWrapping: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.appHeadline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: !allowsWrapping, vertical: true)
    }

    @ViewBuilder
    private var compactAction: some View {
        if let actionTitle, let action {
            Button(actionTitle, action: action)
                .fixedSize(horizontal: true, vertical: false)
                .alikeGlassButton()
        }
    }

    @ViewBuilder
    private var expandedAction: some View {
        if let actionTitle, let action {
            Button(action: action) {
                Text(actionTitle)
                    .frame(maxWidth: .infinity)
            }
            .alikeGlassButton()
        }
    }

    @ViewBuilder
    private var dismissButton: some View {
        if let dismiss {
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .alikeGlassButton()
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text(CleanupL10n.Main.dismissCleanupStatus))
            .accessibilityHint(Text(CleanupL10n.Main.hideThisStatusMessage))
        }
    }
}

/// The banners that sit in the page above the results: the scan the user started, and
/// the prompt to rescan a library that changed.
struct CleanupPersistentBanners: View {
    let scanOperation: ScanOperationState
    let showsRescanPrompt: Bool
    let onRequestScan: @MainActor @Sendable () -> Void

    var body: some View {
        if case .scanning(let progress, .userInitiated) = scanOperation {
            CleanupStatusBanner(
                icon: "arrow.triangle.2.circlepath",
                title: CleanupL10n.Main.refreshingCleanup,
                message: CleanupPresentation.scanningMessage(progress: progress),
                showsProgress: true,
                progress: progress
            )
        } else if case .failed(let message, .userInitiated) = scanOperation {
            CleanupStatusBanner(
                icon: "exclamationmark.triangle.fill",
                title: CleanupL10n.Main.scanFailed,
                message: message
            )
        }
        if showsRescanPrompt {
            CleanupStatusBanner(
                icon: "photo.badge.arrow.down",
                title: CleanupL10n.Main.yourLibraryChanged,
                message: CleanupL10n.Main.runNewScanRefreshCleanup,
                actionTitle: CleanupL10n.Main.rescan,
                action: onRequestScan
            )
        }
    }
}

/// The result of the refresh that follows a cleanup. Its screen owns when it appears and
/// goes away; this only says what it reads.
struct CleanupReconciliationBanner: View {
    let state: CleanupReconciliationState
    let onRequestScan: @MainActor @Sendable () -> Void
    let onDismiss: (UUID) -> Void

    var body: some View {
        switch state {
        case .refreshing:
            EmptyView()
        case .success(let record):
            CleanupStatusBanner(
                icon: "checkmark.circle.fill",
                title: CleanupL10n.Main.photosMovedToRecentlyDeleted(record.deletedCount),
                message: CleanupPresentation.reconciliationMessage(for: state),
                dismiss: { onDismiss(record.id) }
            )
        case .failed(let record, _):
            CleanupStatusBanner(
                icon: "exclamationmark.triangle.fill",
                title: CleanupL10n.Main.refreshRequired,
                message: CleanupPresentation.reconciliationMessage(for: state),
                actionTitle: CleanupL10n.Main.rescan,
                action: onRequestScan,
                dismiss: { onDismiss(record.id) }
            )
        }
    }
}

#Preview("Library Changed") {
    CleanupStatusBanner(
        icon: "photo.badge.arrow.down",
        title: CleanupL10n.Main.yourLibraryChanged,
        message: CleanupL10n.Main.runNewScanRefreshCleanup,
        actionTitle: CleanupL10n.Main.rescan,
        action: {}
    )
    .padding()
}

#Preview("Refresh Failure") {
    CleanupStatusBanner(
        icon: "exclamationmark.triangle.fill",
        title: CleanupL10n.Main.refreshRequired,
        message: CleanupL10n.Main.photosWereDeletedButLibrary,
        actionTitle: CleanupL10n.Main.rescan,
        action: {},
        dismiss: {}
    )
    .padding()
}

#Preview("Persistent Banners") {
    VStack {
        CleanupPersistentBanners(
            scanOperation: .scanning(progress: 0.4, purpose: .userInitiated),
            showsRescanPrompt: true,
            onRequestScan: {}
        )
    }
    .padding()
}

#Preview("Reconciliation Banner") {
    CleanupReconciliationBanner(
        state: .success(
            CleanupCompletionRecord(sourceClusterID: UUID(), deletedCount: 3, estimatedSavingsBytes: 1_000)
        ),
        onRequestScan: {},
        onDismiss: { _ in }
    )
    .padding()
}
