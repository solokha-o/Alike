import Cleanup
import Core
import DesignSystem
import NavigationKit
import Purchases
import PurchasesUI
import SwiftUI

private let scannerSearchingCue = ALIReactionCue(
    id: ALIReactionCueID(eventID: .operation(UUID()), kind: .scanning),
    state: .scanning,
    persistence: .persistent
)

/// The focused scan lifecycle. Review, deletion and history live in Cleanup.
public struct ScannerView: View {
    @State private var viewModel: ScannerViewModel
    @State private var paywall: PresentedPaywall?
    @Binding private var gridColumns: Int
    @Binding private var sensitivity: SensitivityLevel
    @Binding private var shouldStartScan: Bool
    private let subscriptionStore: SubscriptionStore?
    private let onOpenCleanup: () -> Void

    public init(
        workspace: CleanupWorkspaceModel,
        gridColumns: Binding<Int>,
        sensitivity: Binding<SensitivityLevel>,
        shouldStartScan: Binding<Bool> = .constant(false),
        subscriptionStore: SubscriptionStore? = nil,
        onOpenCleanup: @escaping () -> Void = {},
        viewModel: ScannerViewModel? = nil
    ) {
        self._gridColumns = gridColumns
        self._sensitivity = sensitivity
        self._shouldStartScan = shouldStartScan
        self.subscriptionStore = subscriptionStore
        self.onOpenCleanup = onOpenCleanup
        self._viewModel = State(initialValue: viewModel ?? ScannerViewModel(
            workspace: workspace,
            gridColumns: gridColumns.wrappedValue,
            sensitivity: sensitivity.wrappedValue
        ))
    }

    public var body: some View {
        RoutedNavigationStack {
            ScrollView {
                VStack(spacing: Spacing.large) {
                    switch viewModel.state {
                    case .idle: readiness
                    case .scanning(let progress): scanning(progress)
                    case .completed(let summary): completed(summary)
                    case .error(let message): failed(message)
                    }
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(Spacing.large)
            }
            .navigationTitle(Text(appLocalized("Scanner")))
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
        }
        .task { await viewModel.load() }
        .onChange(of: gridColumns) { _, value in viewModel.gridColumns = value }
        .onChange(of: sensitivity) { _, value in viewModel.sensitivity = value }
        .onChange(of: shouldStartScan) { _, requested in
            guard requested else { return }
            Task {
                await startScan()
                shouldStartScan = false
            }
        }
        .sheet(item: $paywall) { paywall in
            SubscriptionPaywallView(context: paywall.context, store: subscriptionStore)
        }
    }

    private var readiness: some View {
        VStack(spacing: Spacing.large) {
            ALIReactionView(
                cue: ALIReactionCue(
                    id: ALIReactionCueID(eventID: .idle, kind: .idle),
                    state: .idle(.ready),
                    persistence: .persistent
                ),
                maximumWidth: 156
            )
            VStack(spacing: Spacing.small) {
                Text(appLocalized("Ready to scan your library"))
                    .font(.appTitle)
                    .multilineTextAlignment(.center)
                Text(appLocalized("Find similar photos and smart cleanup opportunities while keeping every decision in your control."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            allowance
            Button(appLocalized("Start Scanning")) { Task { await startScan() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(.vertical, Spacing.xLarge)
    }

    private func scanning(_ progress: Double) -> some View {
        VStack(spacing: Spacing.large) {
            ALIReactionView(cue: scannerSearchingCue, maximumWidth: 132)
            ProgressView(value: progress) {
                Text(appLocalized("Scanning your photo library"))
                    .font(.appTitle)
            } currentValueLabel: {
                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .foregroundStyle(.secondary)
            }
            .tint(Color.accent)
            Text(appLocalized("You can switch tabs while scanning. Your cleanup results will refresh when it finishes."))
                .font(.appBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.xLarge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(appLocalized("Scanning progress")))
    }

    private func completed(_ summary: ScanSummary) -> some View {
        VStack(spacing: Spacing.large) {
            Image(systemName: summary.clusterCount + summary.cleanupCategoryCandidateCount == 0 ? "checkmark.circle.fill" : "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)
            VStack(spacing: Spacing.small) {
                Text(summary.clusterCount + summary.cleanupCategoryCandidateCount == 0 ? appLocalized("Your library is up to date") : appLocalized("Cleanup opportunities are ready"))
                    .font(.appTitle)
                    .multilineTextAlignment(.center)
                Text(summaryText(summary))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if summary.clusterCount + summary.cleanupCategoryCandidateCount > 0 {
                Button(appLocalized("Review Cleanup")) { onOpenCleanup() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            Button(appLocalized("Scan Again")) { Task { await startScan() } }
                .buttonStyle(.bordered)
            if let offer = viewModel.pendingPostScanPremiumOffer {
                Button {
                    paywall = PresentedPaywall(context: .postFirstScan(
                        similarClusterCount: offer.similarClusterCount,
                        candidateCount: offer.cleanupCategoryCandidateCount,
                        estimatedSavings: ByteCountFormatter.string(fromByteCount: offer.estimatedSavingsBytes, countStyle: .file)
                    ))
                    viewModel.consumePostScanPremiumOffer()
                } label: {
                    Label(appLocalized("Unlock more with Alike Pro"), systemImage: "sparkles.rectangle.stack.fill")
                        .font(.appHeadline)
                }
                .buttonStyle(.bordered)
                .padding(.top, Spacing.small)
            }
        }
        .padding(.vertical, Spacing.xLarge)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: Spacing.large) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(appLocalized("Scan Failed")).font(.appTitle)
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(appLocalized("Retry")) { Task { await startScan() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            if viewModel.hasCompletedScanBaseline {
                Button(appLocalized("Review Existing Cleanup")) { onOpenCleanup() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, Spacing.xLarge)
    }

    @ViewBuilder private var allowance: some View {
        if !viewModel.hasUnlimitedScanAccess {
            Text(String(format: appLocalized("%d of %d free scans remaining"), viewModel.remainingFreeScans, PremiumAccessPolicy.monthlyFreeScanLimit))
                .font(.appCaption)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryText(_ summary: ScanSummary) -> String {
        let count = summary.clusterCount + summary.cleanupCategoryCandidateCount
        guard count > 0 else { return appLocalized("No cleanup opportunities were found in this scan.") }
        let savings = ByteCountFormatter.string(fromByteCount: summary.estimatedSavingsBytes, countStyle: .file)
        return String(format: appLocalized("%d opportunities found • %@ estimated reclaimable"), count, savings)
    }

    private func startScan() async {
        let decision = await viewModel.startScanning()
        if !decision.isAllowed {
            paywall = PresentedPaywall(context: .scanAllowance(
                remaining: viewModel.remainingFreeScans,
                resetDate: viewModel.nextFreeScanResetDate
            ))
        }
    }
}

private struct PresentedPaywall: Identifiable {
    let id = UUID()
    let context: PremiumSurfaceContext
}
