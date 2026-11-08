import SwiftUI
import Photos
import MapKit
import Core
import DesignSystem
import Storage
import NavigationKit
import Purchases
import PurchasesUI

#if os(iOS)

/// Details screen showing all photos in a cluster
public struct ClusterDetailsView: View {
    fileprivate enum Constants {
        static let hostReviewStateRefreshDebounce = Duration.milliseconds(250)
        /// Preview render size: large enough to judge the result on any iPhone,
        /// small enough not to render the full-size image for a preview.
        static let enhancementPreviewSize = CGSize(width: 1_600, height: 1_600)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onReviewStateChanged: (() -> Void)?
    private let onCleanupCompleted: ((CleanupCompletionRecord) -> Void)?
    private let subscriptionStore: SubscriptionStore?

    @State private var viewModel: ClusterDetailsViewModel
    @PhotoGridColumnPreference private var selectedGridColumnCount
    @State private var selectedAsset: SelectedAsset?
    @State private var presentedPremiumFeature: PremiumFeature?
    @State private var enhancementRequest: EnhancementRequest?

    public init(
        cluster: PhotoCluster,
        cleanupService: (any PhotoCleanupService)? = nil,
        cleanupHistoryRepository: CleanupHistoryRepository = FileCleanupHistoryRepository(),
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        subscriptionStore: SubscriptionStore? = nil,
        openSettingsAction: (@MainActor @Sendable () -> Void)? = nil,
        qualityAnalyzer: any PhotoQualityAnalyzing = NoOpPhotoQualityAnalyzer(),
        enhancementService: (any PhotoEnhancementService)? = nil,
        overrideMetrics: (any BestShotOverrideMetricsRepository)? = nil,
        personalizedConfigProvider: BestShotPersonalizedScoringConfigProvider? = nil,
        onReviewStateChanged: (() -> Void)? = nil,
        onCleanupCompleted: ((CleanupCompletionRecord) -> Void)? = nil
    ) {
        self.onReviewStateChanged = onReviewStateChanged
        self.onCleanupCompleted = onCleanupCompleted
        self.subscriptionStore = subscriptionStore
        self._viewModel = State(initialValue: ClusterDetailsViewModel(
            cluster: cluster,
            cleanupService: cleanupService ?? UnsupportedPhotoCleanupService(),
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: premiumAccess,
            openSettingsAction: openSettingsAction,
            qualityAnalyzer: qualityAnalyzer,
            enhancementService: enhancementService,
            overrideMetrics: overrideMetrics,
            personalizedConfigProvider: personalizedConfigProvider
        ))
    }

    init(
        cluster: PhotoCluster,
        viewModel: ClusterDetailsViewModel,
        onReviewStateChanged: (() -> Void)? = nil,
        onCleanupCompleted: ((CleanupCompletionRecord) -> Void)? = nil
    ) {
        self.onReviewStateChanged = onReviewStateChanged
        self.onCleanupCompleted = onCleanupCompleted
        self.subscriptionStore = nil
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            if viewModel.hasLoadedReviewState {
                loadedContent
                    .transition(.opacity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        // A crossfade instead of an instant swap, so the spinner does not get
        // replaced by a wall of content the instant loading finishes.
        .animation(.appSmooth, value: viewModel.hasLoadedReviewState)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isDeleteActionVisible, !viewModel.isDeleting {
                ClusterReviewActionBar(
                    selectedCount: viewModel.selectedCount,
                    onDeleteSelected: requestDeleteConfirmation,
                    isDeleting: viewModel.isDeleting
                )
                .padding(Spacing.xSmall)
                .transition(actionBarTransition)
            }
        }
        .animation(
            viewModel.hasLoadedReviewState ? .appSmooth : nil,
            value: viewModel.displayedAssetIdentifiers
        )
        .animation(viewModel.hasLoadedReviewState ? .appInteractive : nil, value: viewModel.selectedAssetIDs)
        .animation(viewModel.hasLoadedReviewState ? .appInteractive : nil, value: viewModel.reviewStatus)
        .sensoryFeedback(.selection, trigger: viewModel.selectionFeedbackTrigger)
        .sensoryFeedback(.success, trigger: viewModel.successFeedbackTrigger)
        .navigationTitle(Text(DetailsL10n.ClusterDetails.similarPhotos))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isDeleting)
        // The tab bar stays visible on purpose: hiding it here removed and
        // re-added the Cleanup scroll view's bottom safe-area inset on every
        // push/pop, which clamped its content offset and lost the user's place.
        .toolbar {
            if !viewModel.isDeleting {
                if viewModel.isActionBarVisible {
                    ToolbarItem(placement: .topBarTrailing) {
                        ClusterReviewToggle(
                            isConfirmed: viewModel.isReviewConfirmed,
                            keepSummaryText: viewModel.keepSummaryText,
                            hint: ClusterReviewToggle.hint(
                                isConfirmed: viewModel.isReviewConfirmed,
                                selectedCount: viewModel.selectedCount
                            ),
                            onToggle: { viewModel.toggleReviewConfirmation() }
                        )
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    ClusterDetailsOverflowMenu(
                        showsSelectionActions: viewModel.isActionBarVisible && canSelectPhotos,
                        hasSelection: viewModel.selectedCount > 0,
                        onSelectAllExceptBest: { viewModel.selectAllExceptBest() },
                        onClearSelection: { viewModel.clearSelection() }
                    )
                }
            }
        }
        .fullScreenCover(item: $enhancementRequest) { request in
            // Everything here works on the photo frozen when the action was
            // tapped, never on the live Best Shot: a ranking that lands while
            // the cover opens must not retarget it.
            if let requestedAsset = viewModel.asset(withIdentifier: request.assetID) {
                EnhancementPreviewView(
                    asset: requestedAsset,
                    enhancedImage: viewModel.enhancementPreview,
                    state: viewModel.enhancementState,
                    replacesOtherAppEdit: viewModel.isBestShotEditedElsewhere,
                    onApply: { Task { await viewModel.applyEnhancement(for: request.assetID) } },
                    onCancel: viewModel.dismissEnhancementPreview
                )
                .task {
                    await viewModel.enhance(
                        previewSize: Constants.enhancementPreviewSize,
                        for: request.assetID
                    )
                }
            }
        }
        .fullScreenCover(item: $selectedAsset) { selection in
            FullscreenPhotoPagerView(assets: viewModel.assets, selectedIndex: selection.index)
                .photoPagerTransition()
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
            viewModel.deleteConfirmationTitle,
            isPresented: Bindable(viewModel).isDeleteConfirmationPresented
        ) {
            Button(DetailsL10n.Common.cancel, role: .cancel) {}
            Button(DetailsL10n.Common.move, role: .destructive) {
                Task {
                    await viewModel.confirmDelete()
                }
            }
        } message: {
            Text(viewModel.deleteConfirmationMessage)
        }
        .alert(
            viewModel.actionErrorTitle,
            isPresented: Bindable(viewModel).isActionErrorPresented
        ) {
            if viewModel.shouldOfferOpenSettings {
                Button(DetailsL10n.Common.openSettings) {
                    viewModel.openSettings()
                    viewModel.clearActionError()
                }
            }
            Button(DetailsL10n.Common.ok, role: .cancel) {
                viewModel.clearActionError()
            }
        } message: {
            Text(viewModel.actionErrorMessage ?? "")
        }
        .task {
            await viewModel.load()
        }
        .task(id: viewModel.persistedRevision) {
            await notifyHostOfPersistedReviewState()
        }
        .onChange(of: viewModel.pendingCompletionRecord) { _, record in
            guard let record else { return }
            onCleanupCompleted?(record)
            dismiss()
        }
        .onDisappear {
            guard !viewModel.hasCompletedCleanup else { return }
            Task {
                await viewModel.awaitPendingPersistence()
                onReviewStateChanged?()
            }
        }
        .interactiveDismissDisabled(viewModel.isDeleting)
    }

    /// One photo of a cluster is always kept, and that photo is the Best Shot,
    /// so nothing can be selected until there is one.
    private var canSelectPhotos: Bool {
        !viewModel.bestShotAssetID.isEmpty
    }

    private var actionBarTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .move(edge: .bottom).combined(with: .opacity)
    }

    private var loadedContent: some View {
        let displayedAssets = viewModel.displayedAssets
        let gridColumns = selectedGridColumnCount

        return LazyVStack(spacing: Spacing.medium) {
            if viewModel.isDeleting {
                AlikeCleanupProgressView(
                    selectedCount: viewModel.selectedCount,
                    estimatedSavingsText: viewModel.estimatedSavingsText,
                    isExecuting: viewModel.isDeleting
                )
            } else {
                if viewModel.hasAssets {
                    ClusterReviewSummaryCard(
                        assetCount: viewModel.assetCount,
                        bestShotLabel: viewModel.bestShotLabel,
                        bestShotConfidence: viewModel.bestShotConfidence,
                        isChoosingBestShot: viewModel.isRankingQualityPending,
                        bestShotReasonCodes: viewModel.bestShotReasonCodes,
                        isBestShotEditedElsewhere: viewModel.isBestShotEditedElsewhere,
                        selectedCount: viewModel.selectedCount,
                        estimatedSavingsText: viewModel.estimatedSavingsText,
                        maximumEstimatedSavingsText: viewModel.maximumEstimatedSavingsText,
                        reviewStatus: viewModel.reviewStatus,
                        isReviewConfirmed: viewModel.isReviewConfirmed,
                        alikeReactionCue: viewModel.currentAlikeReaction,
                        bestShotCelebrationCue: viewModel.bestShotCelebrationCue,
                        onBestShotCelebrationDismissed: viewModel.consumeBestShotCelebration
                    )
                }

                if viewModel.requiresPremiumForCurrentSelection {
                    BatchCleanupUpsellCard(
                        selectedCount: viewModel.selectedCount,
                        estimatedSavings: viewModel.estimatedSavingsText,
                        onUpgrade: { presentedPremiumFeature = .batchCleanup },
                        onContinueFree: {
                            Task {
                                await viewModel.continueWithSingleFreeSelection()
                            }
                        }
                    )
                }

                if !viewModel.hasAssets {
                    ContentUnavailableView {
                        Label(DetailsL10n.ClusterDetails.noPhotosAvailable, systemImage: "photo")
                    }
                    .padding(.top, 80)
                } else {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: Spacing.xxSmall),
                            count: gridColumns
                        ),
                        spacing: Spacing.xxSmall
                    ) {
                        ForEach(displayedAssets, id: \.localIdentifier) { asset in
                            SelectablePhotoThumbnail(
                                asset: asset,
                                thumbnailAspectRatio: 1,
                                // Hidden until the measured ranking settles, so
                                // the star never hops between photos.
                                isBestShot: viewModel.isBestShotVisible
                                    && viewModel.isBestShot(asset.localIdentifier),
                                bestShotConfidence: viewModel.bestShotConfidence,
                                isSelected: viewModel.isSelected(asset.localIdentifier),
                                canSelect: canSelectPhotos,
                                onToggleSelection: {
                                    viewModel.toggleSelection(for: asset.localIdentifier)
                                },
                                onOpenOriginal: {
                                    if let index = viewModel.assetIndex(for: asset.localIdentifier) {
                                        selectedAsset = SelectedAsset(asset: asset, index: index)
                                    }
                                },
                                onMakeBestShot: {
                                    viewModel.setBestShot(asset.localIdentifier)
                                },
                                isEnhanced: viewModel.isEnhanced(asset.localIdentifier),
                                enhancementState: viewModel.isBestShot(asset.localIdentifier)
                                    ? viewModel.enhancementState
                                    : .unavailable,
                                onEnhance: viewModel.isBestShot(asset.localIdentifier)
                                    && viewModel.isEnhancementActionVisible
                                    ? {
                                        // Freeze the photo at the tap, so a late
                                        // ranking cannot retarget the cover.
                                        if let assetID = viewModel.beginEnhancementRequest() {
                                            enhancementRequest = EnhancementRequest(assetID: assetID)
                                        }
                                    }
                                    : nil,
                                onRevertEnhancement: viewModel.isBestShot(asset.localIdentifier)
                                    && viewModel.isEnhancementActionVisible
                                    ? { Task { await viewModel.revertEnhancement() } }
                                    : nil,
                                swipeActions: PhotoTileSwipeAction.available(
                                    isSelected: viewModel.isSelected(asset.localIdentifier),
                                    isBestShot: viewModel.isBestShot(asset.localIdentifier),
                                    canSelect: canSelectPhotos,
                                    canMakeBestShot: true
                                ),
                                onSwipeAction: { action in
                                    action.perform(on: viewModel, assetID: asset.localIdentifier)
                                }
                            )
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.94).combined(with: .opacity),
                                    removal: .scale(scale: 0.94).combined(with: .opacity)
                                )
                            )
                        }
                    }
                    .photoTileSwipeActionsContainer()
                }
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.small)
        .padding(.bottom, Spacing.medium)
    }
}

private extension ClusterDetailsView {
    func requestDeleteConfirmation() {
        if viewModel.requestDeleteConfirmation() == .requiresPremium {
            presentedPremiumFeature = .batchCleanup
        }
    }

    /// Lets the host reload review state while this screen is still on top, so
    /// the cleanup screen behind it is already up to date when it is revealed.
    /// The debounce is cancelled and restarted by every further persisted edit,
    /// so a burst of selection taps refreshes the host once.
    func notifyHostOfPersistedReviewState() async {
        guard viewModel.persistedRevision > 0 else { return }
        do {
            try await Task.sleep(for: Constants.hostReviewStateRefreshDebounce)
        } catch {
            return
        }
        onReviewStateChanged?()
    }
}

private struct SelectedAsset: Identifiable {
    let asset: PHAsset
    let index: Int
    var id: String { asset.localIdentifier }
}

/// Identifies one presentation of the enhancement preview sheet.
private struct EnhancementRequest: Identifiable {
    let id = UUID()
    /// The photo this preview belongs to, frozen when the action was tapped.
    let assetID: String
}

#else

public struct ClusterDetailsView: View {
    let cluster: PhotoCluster

    public init(
        cluster: PhotoCluster,
        cleanupService: (any PhotoCleanupService)? = nil,
        cleanupHistoryRepository: CleanupHistoryRepository = FileCleanupHistoryRepository(),
        premiumAccess: any PremiumAccessControlling = PremiumAccessController(),
        subscriptionStore: SubscriptionStore? = nil,
        openSettingsAction: (@MainActor @Sendable () -> Void)? = nil,
        onReviewStateChanged: (() -> Void)? = nil,
        onCleanupCompleted: ((CleanupCompletionRecord) -> Void)? = nil
    ) {
        self.cluster = cluster
    }

    public var body: some View {
        ContentUnavailableView {
            Label(DetailsL10n.ClusterDetails.similarPhotos, systemImage: "photo.stack")
        } description: {
            Text(DetailsL10n.ClusterDetails.clusterDetailsAvailableIOS)
        }
    }
}

#endif

// MARK: - Preview

// PhotoCluster.mock only exists in DEBUG, and #Preview is expanded in every
// configuration, so this preview has to be gated or the Release build fails
// to compile.
#if DEBUG
#Preview {
    RoutedNavigationStack {
        ClusterDetailsView(cluster: .mock)
    }
}
#endif
