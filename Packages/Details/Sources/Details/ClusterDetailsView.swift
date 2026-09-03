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
            overrideMetrics: overrideMetrics
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
            if viewModel.isDeleteActionVisible && !viewModel.isDeleting {
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
        .sensoryFeedback(.selection, trigger: viewModel.selectedAssetIDs.count)
        .sensoryFeedback(.success, trigger: viewModel.bestShotAssetID)
        .sensoryFeedback(.success, trigger: viewModel.reviewStatus == .reviewed)
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
                        reviewToggle
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    overflowMenu
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

    /// Finishing the review is a state the user flips, not a step in a flow, so
    /// it reads as a toggle next to the title instead of a third button
    /// competing with the destructive action at the bottom.
    private var reviewToggle: some View {
        Button {
            viewModel.toggleReviewConfirmation()
        } label: {
            Image(systemName: viewModel.isReviewConfirmed ? "checkmark.seal.fill" : "checkmark.seal")
                .symbolEffect(.bounce, value: reduceMotion ? false : viewModel.isReviewConfirmed)
        }
        .tint(viewModel.isReviewConfirmed ? Color.statusReviewed : nil)
        .accessibilityLabel(Text(
            viewModel.isReviewConfirmed
                ? DetailsL10n.Common.reviewed
                : DetailsL10n.ClusterDetails.markReviewed
        ))
        .accessibilityValue(Text(viewModel.keepSummaryText))
        .accessibilityHint(Text(reviewToggleHint))
        .accessibilityAddTraits(viewModel.isReviewConfirmed ? [.isSelected] : [])
    }

    private var reviewToggleHint: String {
        if viewModel.isReviewConfirmed {
            return DetailsL10n.ClusterDetails.doubleTapReopenThisCluster
        }
        return viewModel.selectedCount == 0
            ? DetailsL10n.ClusterDetails.finishesReviewKeepsEveryPhoto
            : DetailsL10n.ClusterDetails.finishesReviewKeepsPhotosDid
    }

    /// Two labelled sections instead of one flat list: acting on the selection
    /// and changing how the grid looks are different jobs, and the column
    /// options stay folded into a submenu so they never outnumber the actions.
    private var overflowMenu: some View {
        Menu {
            if viewModel.isActionBarVisible {
                Section(DetailsL10n.ClusterDetails.selection) {
                    Button {
                        viewModel.selectAllExceptBest()
                    } label: {
                        Label(DetailsL10n.ClusterDetails.selectAllExceptBest, systemImage: "checkmark.circle")
                    }

                    if viewModel.selectedCount > 0 {
                        Button {
                            viewModel.clearSelection()
                        } label: {
                            Label(DetailsL10n.Common.clearSelection, systemImage: "xmark.circle")
                        }
                    }
                }
            }

            Section(DetailsL10n.ClusterDetails.view) {
                PhotoGridColumnsPicker()
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(Text(DetailsL10n.ClusterDetails.moreOptions))
        .accessibilityHint(Text(DetailsL10n.ClusterDetails.selectionShortcutsAndGridLayout))
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
                                    : nil
                            )
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.94).combined(with: .opacity),
                                    removal: .scale(scale: 0.94).combined(with: .opacity)
                                )
                            )
                        }
                    }
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

struct SelectablePhotoThumbnail: View {
    let asset: PHAsset
    let thumbnailAspectRatio: CGFloat
    let isBestShot: Bool
    var bestShotConfidence: BestShotConfidence = .automatic
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onOpenOriginal: () -> Void
    var onMakeBestShot: (() -> Void)?
    var isEnhanced = false
    var enhancementState: PhotoEnhancementState = .unavailable
    var onEnhance: (() -> Void)?
    var onRevertEnhancement: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var image: UIImage?
    @State private var imageLoadState = PhotoImageLoadState()
    @State private var imageLoadAttempt = 0
    @State private var showingMetadata = false

    var body: some View {
        ZStack {
            Button(action: onToggleSelection) {
                PhotoThumbnailAspectRatioLayout(aspectRatio: thumbnailAspectRatio) {
                    ZStack {
                        Color.secondary.opacity(ColorOpacity.placeholderFill)

                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else if imageLoadState.phase == .loading {
                            ProgressView()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(thumbnailShape)
                .overlay {
                    if isSelected {
                        thumbnailShape
                            .fill(Color.accent.opacity(ColorOpacity.selectionOverlay))
                            .transition(.opacity)
                    }
                }
                .overlay {
                    thumbnailShape
                        .stroke(borderColor, lineWidth: borderLineWidth)
                }
                .overlay(alignment: .topLeading) {
                    if isBestShot {
                        Label {
                            Text(bestShotConfidence.badgeTitle)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: bestShotConfidence.badgeSymbolName)
                                .foregroundStyle(Color.heroGold)
                        }
                            .font(.caption.bold())
                            .padding(.horizontal, Spacing.xSmall)
                            .padding(.vertical, Spacing.xxSmall)
                            .background(.regularMaterial, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(Color.heroGold.opacity(0.7), lineWidth: 1)
                            }
                            .padding(Spacing.xSmall)
                            .transition(bestShotBadgeTransition)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isEnhanced {
                        enhancedBadge
                            .padding(Spacing.xSmall)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .center) {
                    if enhancementState.isBusy {
                        ProgressView()
                            .padding(Spacing.small)
                            .background(.regularMaterial, in: Circle())
                    }
                }
                .animation(.appInteractiveFast, value: isEnhanced)
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accent)
                            .background(.white, in: Circle())
                            .padding(Spacing.xSmall)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .animation(.appInteractiveFast, value: isSelected)
                .animation(.appInteractiveFast, value: isBestShot)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityValue(Text(accessibilityValue))
            .accessibilityHint(Text(accessibilityHint))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityActions {
                if let onMakeBestShot, !isBestShot {
                    Button(DetailsL10n.ClusterDetails.makeBestShot, action: onMakeBestShot)
                }
                if isEnhanced, let onRevertEnhancement {
                    Button(DetailsL10n.ClusterDetails.revertToOriginal, action: onRevertEnhancement)
                } else if let onEnhance {
                    Button(DetailsL10n.ClusterDetails.enhance, action: onEnhance)
                }
            }

            if imageLoadState.phase == .failed {
                PhotoLoadFailureView {
                    imageLoadAttempt += 1
                }
                .background(.regularMaterial, in: thumbnailShape)
            }
        }
        .contentShape(.interaction, thumbnailShape)
        .contentShape(.contextMenuPreview, thumbnailShape)
        .contextMenu {
            enhancementMenuItems

            if let onMakeBestShot, !isBestShot {
                Button {
                    onMakeBestShot()
                } label: {
                    Label {
                        Text(DetailsL10n.ClusterDetails.makeBestShot)
                    } icon: {
                        Image(systemName: "star")
                    }
                }
            }

            Button {
                showingMetadata = true
            } label: {
                Label {
                    Text(DetailsL10n.ClusterDetails.showInfo)
                } icon: {
                    Image(systemName: "info.circle")
                }
            }
            
            Button {
                onOpenOriginal()
            } label: {
                Label {
                    Text(DetailsL10n.ClusterDetails.openOriginal)
                } icon: {
                    Image(systemName: "arrow.up.forward.square")
                }
            }
        } preview: {
            contextMenuPreview
        }
        .sheet(isPresented: $showingMetadata) {
            MetadataView(asset: asset)
                .presentationDetents([.medium, .large])
        }
        .task(id: imageLoadTaskID) {
            await loadThumbnail()
        }
    }

    private var borderColor: Color {
        if isBestShot {
            return .heroGold.opacity(0.9)
        }
        if isSelected {
            return .accent
        }
        return .clear
    }

    private var borderLineWidth: CGFloat {
        (isBestShot || isSelected) ? 2 : 0
    }

    /// A settle-in fade rather than a pop when the measured ranking lands;
    /// under reduce motion the scale drops and only the fade remains.
    private var bestShotBadgeTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity)
    }

    private var thumbnailShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous)
    }

    private var thumbnailTargetSize: CGSize {
        thumbnailAspectRatio == 1
            ? CGSize(width: 1_000, height: 1_000)
            : CGSize(width: 300, height: 300)
    }

    private var imageLoadTaskID: String {
        "\(asset.localIdentifier)#\(imageLoadAttempt)"
    }

    @MainActor
    private func loadThumbnail() async {
        image = nil
        let generation = imageLoadState.begin()
        do {
            guard let loadedImage = try await asset.loadImage(targetSize: thumbnailTargetSize) else {
                imageLoadState.resolve(.failed, generation: generation)
                return
            }
            guard imageLoadState.resolve(.loaded, generation: generation) else { return }
            image = loadedImage
        } catch is CancellationError {
            imageLoadState.resolve(.cancelled, generation: generation)
        } catch {
            imageLoadState.resolve(.failed, generation: generation)
        }
    }

    private var contextMenuPreview: some View {
        ZStack {
            Color.secondary.opacity(ColorOpacity.placeholderFill)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if imageLoadState.phase == .loading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: contextMenuPreviewWidth,
            height: contextMenuPreviewWidth / thumbnailAspectRatio
        )
        .clipShape(thumbnailShape)
    }

    private var contextMenuPreviewWidth: CGFloat { 240 }

    /// One step in each direction: enhance, or put the original back.
    @ViewBuilder
    private var enhancementMenuItems: some View {
        if isEnhanced, let onRevertEnhancement {
            Button(action: onRevertEnhancement) {
                Label {
                    Text(DetailsL10n.ClusterDetails.revertToOriginal)
                } icon: {
                    Image(systemName: "arrow.uturn.backward")
                }
            }
            .disabled(enhancementState.isBusy)
        } else if let onEnhance {
            Button(action: onEnhance) {
                Label {
                    Text(DetailsL10n.ClusterDetails.enhance)
                } icon: {
                    Image(systemName: "wand.and.stars")
                }
            }
            .disabled(enhancementState.isBusy)
        }
    }

    /// Permanent marker that this photo is showing Alike's enhanced version.
    private var enhancedBadge: some View {
        Label {
            Text(DetailsL10n.ClusterDetails.enhanced)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(Color.accent)
        }
        .font(.caption2.bold())
        .padding(.horizontal, Spacing.xSmall)
        .padding(.vertical, Spacing.xxSmall)
        .background(.regularMaterial, in: Capsule())
    }

    private var accessibilityLabel: String {
        if isBestShot {
            return bestShotConfidence.badgeTitle
        }
        if isSelected {
            return DetailsL10n.ClusterDetails.selectedForCleanupReview
        }
        return DetailsL10n.ClusterDetails.notSelected
    }

    private var accessibilityValue: String {
        if isBestShot {
            return bestShotConfidence.badgeTitle
        }
        return isSelected ? DetailsL10n.ClusterDetails.selected : DetailsL10n.ClusterDetails.notSelected
    }

    private var accessibilityHint: String {
        if isBestShot {
            return DetailsL10n.ClusterDetails.thisPhotoKeptAsBest
        }
        return isSelected
            ? DetailsL10n.ClusterDetails.doubleTapRemoveThisPhoto
            : DetailsL10n.ClusterDetails.doubleTapSelectThisPhoto
    }
}

// MARK: - Metadata View
struct MetadataView: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss

    private var metadata: AssetMetadata {
        asset.displayMetadata
    }
    
    var body: some View {
        RoutedNavigationStack {
            List {
                PhotoInfoPreview(asset: asset)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                Section {
                    LabeledContent {
                        Text(metadata.resolution)
                    } label: {
                        Text(DetailsL10n.ClusterDetails.resolution)
                    }

                    LabeledContent {
                        Text(formattedMegapixels)
                    } label: {
                        Text(DetailsL10n.ClusterDetails.megapixels)
                    }

                    LabeledContent {
                        Text(photoType)
                    } label: {
                        Text(DetailsL10n.ClusterDetails.type)
                    }

                    LabeledContent {
                        Text(metadata.isFavorite ? DetailsL10n.ClusterDetails.yes : DetailsL10n.ClusterDetails.no)
                    } label: {
                        Text(DetailsL10n.ClusterDetails.favorite)
                    }
                } header: {
                    Text(DetailsL10n.ClusterDetails.details)
                }

                if metadata.creationDate != nil || metadata.modificationDate != nil {
                    Section {
                        if metadata.creationDate != nil {
                            LabeledContent {
                                Text(metadata.formattedCreationDate)
                            } label: {
                                Text(DetailsL10n.ClusterDetails.created)
                            }
                        }

                        if let modified = metadata.formattedModificationDate {
                            LabeledContent {
                                Text(modified)
                            } label: {
                                Text(DetailsL10n.ClusterDetails.modified)
                            }
                        }
                    } header: {
                        Text(DetailsL10n.ClusterDetails.dates)
                    }
                }

                if let location = metadata.location {
                    PhotoInfoLocationSection(location: location)
                }
            }
            .navigationTitle(Text(DetailsL10n.ClusterDetails.photoInfo))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text(DetailsL10n.ClusterDetails.done)
                    }
                }
            }
        }
    }

    private var formattedMegapixels: String {
        let value = metadata.megapixelCount.formatted(
            FloatingPointFormatStyle<Double>.alikeDecimal.precision(.fractionLength(0...1))
        )
        return String(format: DetailsL10n.ClusterDetails.mp, value)
    }

    private var photoType: String {
        guard !metadata.photoTraits.isEmpty else {
            return DetailsL10n.ClusterDetails.photo
        }

        return metadata.photoTraits.map { trait in
            switch trait {
            case .screenshot:
                DetailsL10n.ClusterDetails.screenshot
            case .panorama:
                DetailsL10n.ClusterDetails.panorama
            case .livePhoto:
                DetailsL10n.ClusterDetails.livePhoto
            case .hdr:
                DetailsL10n.ClusterDetails.hdr
            case .depthEffect:
                DetailsL10n.ClusterDetails.depthEffect
            }
        }
        .joined(separator: ", ")
    }
}

private struct PhotoInfoPreview: View {
    let asset: PHAsset

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.secondary.opacity(ColorOpacity.placeholderFill)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .accessibilityLabel(Text(DetailsL10n.Common.photoPreview))
            } else if isLoading {
                ProgressView()
                    .accessibilityLabel(Text(DetailsL10n.Common.loadingPhotoPreview))
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(DetailsL10n.Common.photoPreviewUnavailable))
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .task(id: asset.localIdentifier) {
            defer { isLoading = false }
            image = try? await asset.loadImage(targetSize: CGSize(width: 800, height: 600))
        }
    }
}

private struct PhotoInfoLocationSection: View {
    let location: AssetLocation

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }

    var body: some View {
        Section {
            Map(initialPosition: .region(region), interactionModes: []) {
                Marker(DetailsL10n.ClusterDetails.photoLocation, coordinate: coordinate)
            }
            .frame(height: 160)
            .listRowInsets(EdgeInsets())
            .accessibilityLabel(Text(DetailsL10n.ClusterDetails.mapShowingWherePhotoWas))

            Button {
                openInMaps()
            } label: {
                Label(DetailsL10n.ClusterDetails.openInMaps, systemImage: "map")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityHint(Text(DetailsL10n.ClusterDetails.opensPhotoLocationMaps))
        } header: {
            Text(DetailsL10n.ClusterDetails.location)
        }
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = DetailsL10n.ClusterDetails.photoLocation
        mapItem.openInMaps()
    }
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

struct MetadataView: View {
    var body: some View {
        EmptyView()
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
