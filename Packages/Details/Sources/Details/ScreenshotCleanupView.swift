import SwiftUI
import Photos
import Core
import DesignSystem
import Storage
import Purchases
import PurchasesUI

#if os(iOS)

public struct ScreenshotCleanupView: View {
    @Environment(\.dismiss) private var dismiss

    private let assets: [PHAsset]
    private let onCleanupCompleted: ((CleanupCompletionRecord) -> Void)?
    private let subscriptionStore: SubscriptionStore?
    @State private var viewModel: ScreenshotCleanupViewModel
    @PhotoGridColumnPreference private var selectedGridColumnCount
    @State private var selectedAsset: PresentedScreenshotAsset?
    @State private var presentedPremiumFeature: PremiumFeature?
    @State private var didCompleteCleanup = false

    public init(
        assets: [PHAsset],
        sourceCategory: CleanupCategoryKind = .screenshots,
        cleanupService: (any PhotoCleanupService)? = nil,
        cleanupHistoryRepository: CleanupHistoryRepository = FileCleanupHistoryRepository(),
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        subscriptionStore: SubscriptionStore? = nil,
        openSettingsAction: (@MainActor @Sendable () -> Void)? = nil,
        onCleanupCompleted: ((CleanupCompletionRecord) -> Void)? = nil
    ) {
        self.assets = assets
        self.onCleanupCompleted = onCleanupCompleted
        self.subscriptionStore = subscriptionStore
        self._viewModel = State(initialValue: ScreenshotCleanupViewModel(
            assets: assets,
            sourceCategory: sourceCategory,
            cleanupService: cleanupService ?? UnsupportedPhotoCleanupService(),
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: premiumAccess,
            openSettingsAction: openSettingsAction
        ))
    }

    public var body: some View {
        ScrollView {
            if viewModel.isDeleting {
                AlikeCleanupProgressView(
                    selectedCount: viewModel.selectedCount,
                    estimatedSavingsText: viewModel.estimatedSavingsText,
                    isExecuting: viewModel.isDeleting
                )
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
            } else if assets.isEmpty {
                emptyState
            } else {
                screenshotGrid
            }
        }
        .animation(.appInteractive, value: viewModel.selectedAssetIDs)
        .sensoryFeedback(.selection, trigger: viewModel.selectedAssetIDs.count)
        .safeAreaInset(edge: .top) {
            if !viewModel.isDeleting {
                header
            }
        }
        .navigationTitle(Text(viewModel.presentation.navigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(Text(DetailsL10n.Common.close))
                .disabled(viewModel.isDeleting)
            }

            if !viewModel.isDeleting {
                ToolbarItem(placement: .topBarTrailing) {
                    columnsMenu
                }
            }
        }
        .fullScreenCover(item: $selectedAsset) { selection in
            FullscreenPhotoPagerView(assets: assets, selectedIndex: selection.index)
        }
        .sheet(item: $presentedPremiumFeature) { _ in
            SubscriptionPaywallView(
                context: .batchCleanup(
                    selectedCount: viewModel.selectedCount,
                    estimatedSavings: viewModel.estimatedSavingsText
                ),
                store: subscriptionStore
            )
        }
        .alert(
            deleteConfirmationTitle,
            isPresented: Bindable(viewModel).isDeleteConfirmationPresented
        ) {
            Button(DetailsL10n.Common.cancel, role: .cancel) {}
            Button(DetailsL10n.Common.move, role: .destructive) {
                Task {
                    await viewModel.confirmDelete()
                }
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .alert(
            DetailsL10n.Common.cleanupUnavailable,
            isPresented: Binding(
                get: { viewModel.deleteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.clearDeleteError()
                    }
                }
            )
        ) {
            if viewModel.shouldOfferOpenSettings {
                Button(DetailsL10n.Common.openSettings) {
                    viewModel.openSettings()
                    viewModel.clearDeleteError()
                }
            }
            Button(DetailsL10n.Common.ok, role: .cancel) {
                viewModel.clearDeleteError()
            }
        } message: {
            Text(viewModel.deleteErrorMessage ?? "")
        }
        .onChange(of: viewModel.pendingCompletionRecord) { _, record in
            guard let record else { return }
            didCompleteCleanup = true
            onCleanupCompleted?(record)
            dismiss()
        }
        .interactiveDismissDisabled(viewModel.isDeleting)
    }
}

private extension ScreenshotCleanupView {
    var emptyState: some View {
        ContentUnavailableView {
            Label(
                viewModel.presentation.emptyTitle,
                systemImage: viewModel.presentation.systemImageName
            )
        } description: {
            Text(viewModel.presentation.emptyDescription)
        }
        .padding(.top, 80)
    }

    var screenshotGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Spacing.xxSmall),
                count: selectedGridColumnCount
            ),
            spacing: Spacing.xxSmall
        ) {
            ForEach(assets, id: \.localIdentifier) { asset in
                SelectablePhotoThumbnail(
                    asset: asset,
                    thumbnailAspectRatio: 1,
                    isBestShot: false,
                    isSelected: viewModel.isSelected(asset.localIdentifier),
                    onToggleSelection: {
                        viewModel.toggleSelection(for: asset.localIdentifier)
                    },
                    onOpenOriginal: {
                        openOriginal(for: asset)
                    }
                )
            }
        }
        .allowsHitTesting(!viewModel.isDeleting)
        .padding(.horizontal, Spacing.medium)
        .padding(.bottom, Spacing.medium)
    }

    var header: some View {
        VStack(spacing: Spacing.small) {
            ScreenshotCleanupSummaryCard(
                category: viewModel.sourceCategory,
                assetCount: viewModel.assetCount,
                selectedCount: viewModel.selectedCount,
                estimatedSavingsText: viewModel.estimatedSavingsText,
                maximumEstimatedSavingsText: viewModel.maximumEstimatedSavingsText
            )

            ScreenshotCleanupActionBar(
                onSelectAll: viewModel.selectAll,
                onClearSelection: viewModel.clearSelection,
                onDeleteSelected: requestDeleteConfirmation,
                isDeleteActionVisible: viewModel.isDeleteActionVisible,
                isDeleting: viewModel.isDeleting
            )
            .disabled(viewModel.isDeleting)

            if viewModel.requiresPremiumForCurrentSelection {
                BatchCleanupUpsellCard(
                    selectedCount: viewModel.selectedCount,
                    estimatedSavings: viewModel.estimatedSavingsText,
                    onUpgrade: { presentedPremiumFeature = .batchCleanup },
                    onContinueFree: viewModel.continueWithSingleFreeSelection
                )
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.small)
        .padding(.bottom, Spacing.medium)
        .background(.regularMaterial)
    }

    var columnsMenu: some View {
        PhotoGridColumnsMenu()
    }

    func requestDeleteConfirmation() {
        if viewModel.requestDeleteConfirmation() == .requiresPremium {
            presentedPremiumFeature = .batchCleanup
        }
    }

    var deleteConfirmationTitle: String {
        viewModel.selectedCount == 1
            ? viewModel.presentation.alertSingularTitleFormat
            : String(
                format: viewModel.presentation.alertPluralTitleFormat,
                viewModel.selectedCount
            )
    }

    var deleteConfirmationMessage: String {
        viewModel.selectedCount == 1
            ? String(
                format: viewModel.presentation.alertSingularMessageFormat,
                viewModel.estimatedSavingsText
            )
            : String(
                format: viewModel.presentation.alertPluralMessageFormat,
                viewModel.estimatedSavingsText
            )
    }

    func openOriginal(for asset: PHAsset) {
        guard let index = assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) else {
            return
        }
        selectedAsset = PresentedScreenshotAsset(asset: asset, index: index)
    }
}

#else

public struct ScreenshotCleanupView: View {
    public init(
        assets: [PHAsset],
        sourceCategory: CleanupCategoryKind = .screenshots,
        cleanupService: (any PhotoCleanupService)? = nil,
        cleanupHistoryRepository: CleanupHistoryRepository = FileCleanupHistoryRepository(),
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        subscriptionStore: SubscriptionStore? = nil,
        openSettingsAction: (@MainActor @Sendable () -> Void)? = nil,
        onCleanupCompleted: ((CleanupCompletionRecord) -> Void)? = nil
    ) {}

    public var body: some View {
        ContentUnavailableView {
            Label(DetailsL10n.ScreenshotCleanup.screenshots, systemImage: "camera.viewfinder")
        } description: {
            Text(DetailsL10n.ScreenshotCleanup.screenshotCleanupAvailableIOS)
        }
    }
}

#endif
