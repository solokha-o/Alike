import Cleanup
import Core
import DesignSystem
import NavigationKit
import Purchases
import PurchasesUI
import SwiftUI

/// The focused scan lifecycle. Review, deletion and history live in Cleanup.
public struct ScannerView: View {
    @State private var viewModel: ScannerViewModel
    @State private var paywall: PresentedPaywall?
    @Binding private var sensitivity: SensitivityLevel
    @Binding private var shouldStartScan: Bool
    private let subscriptionStore: SubscriptionStore?
    private let onOpenCleanup: () -> Void

    public init(
        workspace: CleanupWorkspaceModel,
        sensitivity: Binding<SensitivityLevel>,
        shouldStartScan: Binding<Bool> = .constant(false),
        subscriptionStore: SubscriptionStore? = nil,
        onOpenCleanup: @escaping () -> Void = {},
        viewModel: ScannerViewModel? = nil
    ) {
        self._sensitivity = sensitivity
        self._shouldStartScan = shouldStartScan
        self.subscriptionStore = subscriptionStore
        self.onOpenCleanup = onOpenCleanup
        self._viewModel = State(initialValue: viewModel ?? ScannerViewModel(
            workspace: workspace,
            sensitivity: sensitivity.wrappedValue
        ))
    }

    public var body: some View {
        RoutedNavigationStack {
            ScrollView {
                VStack(spacing: Spacing.medium) {
                    ScannerHomeHero(
                        presentation: homePresentation,
                        onAction: perform
                    )

                    if homePresentation.progress == nil {
                        supportingContent

                        if viewModel.pendingPostScanPremiumOffer != nil {
                            ScannerPremiumOfferCard(action: presentPremiumOffer)
                        }
                    }
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(Spacing.medium)
            }
            .navigationTitle(Text(appLocalized("Scanner")))
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
        }
        .task { await viewModel.load() }
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

    private var homePresentation: ScannerHomePresentation {
        .resolve(
            state: viewModel.state,
            hasLibraryChanged: viewModel.workspace.shouldShowRescanPrompt,
            hasCompletedScanBaseline: viewModel.hasCompletedScanBaseline,
            scanEventID: viewModel.scanEventID
        )
    }

    private var allowancePresentation: ScannerAllowancePresentation? {
        .resolve(
            hasUnlimitedAccess: viewModel.hasUnlimitedScanAccess,
            remainingScans: viewModel.remainingFreeScans,
            totalScans: PremiumAccessPolicy.monthlyFreeScanLimit
        )
    }

    @ViewBuilder
    private var supportingContent: some View {
        if let summary = viewModel.librarySummary {
            ScannerLibraryStatusCard(
                summary: summary,
                isStale: viewModel.workspace.shouldShowRescanPrompt,
                allowance: allowancePresentation
            )
        } else {
            ScannerScanScopeCard(allowance: allowancePresentation)
        }
    }

    private func perform(_ action: ScannerHomeAction) {
        switch action {
        case .startScanning:
            Task { await startScan() }
        case .openCleanup:
            onOpenCleanup()
        }
    }

    private func presentPremiumOffer() {
        guard let offer = viewModel.pendingPostScanPremiumOffer else { return }
        paywall = PresentedPaywall(context: .postFirstScan(
            similarClusterCount: offer.similarClusterCount,
            candidateCount: offer.cleanupCategoryCandidateCount,
            estimatedSavings: ByteCountFormatter.string(
                fromByteCount: offer.estimatedSavingsBytes,
                countStyle: .file
            )
        ))
        viewModel.consumePostScanPremiumOffer()
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
