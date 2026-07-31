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
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let onReviewStateChanged: (() -> Void)?
    private let onCleanupCompleted: ((CleanupCompletionRecord) -> Void)?
    private let subscriptionStore: SubscriptionStore?

    @State private var viewModel: ClusterDetailsViewModel
    @State private var compactGridColumns = AdaptivePhotoGridLayoutPolicy.compact.defaultColumnCount
    @State private var regularGridColumns = AdaptivePhotoGridLayoutPolicy.regular.defaultColumnCount
    @State private var selectedAsset: SelectedAsset?
    @State private var presentedPremiumFeature: PremiumFeature?

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
        self.onReviewStateChanged = onReviewStateChanged
        self.onCleanupCompleted = onCleanupCompleted
        self.subscriptionStore = subscriptionStore
        self._viewModel = State(initialValue: ClusterDetailsViewModel(
            cluster: cluster,
            cleanupService: cleanupService ?? UnsupportedPhotoCleanupService(),
            cleanupHistoryRepository: cleanupHistoryRepository,
            premiumAccess: premiumAccess,
            openSettingsAction: openSettingsAction
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
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 360)
            }
        }
        .frame(maxWidth: .infinity)
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
        .navigationTitle(Text(appLocalized("Similar Photos")))
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
            Button(appLocalized("Cancel"), role: .cancel) {}
            Button(appLocalized("Move"), role: .destructive) {
                Task {
                    await viewModel.confirmDelete()
                }
            }
        } message: {
            Text(viewModel.deleteConfirmationMessage)
        }
        .alert(
            appLocalized("Cleanup Unavailable"),
            isPresented: Bindable(viewModel).isDeleteErrorPresented
        ) {
            if viewModel.shouldOfferOpenSettings {
                Button(appLocalized("Open Settings")) {
                    viewModel.openSettings()
                    viewModel.clearDeleteError()
                }
            }
            Button(appLocalized("OK"), role: .cancel) {
                viewModel.clearDeleteError()
            }
        } message: {
            Text(viewModel.deleteErrorMessage ?? "")
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
                ? appLocalized("Reviewed")
                : appLocalized("Mark Reviewed")
        ))
        .accessibilityValue(Text(viewModel.keepSummaryText))
        .accessibilityHint(Text(reviewToggleHint))
        .accessibilityAddTraits(viewModel.isReviewConfirmed ? [.isSelected] : [])
    }

    private var reviewToggleHint: String {
        if viewModel.isReviewConfirmed {
            return appLocalized("Double tap to reopen this cluster for review")
        }
        return viewModel.selectedCount == 0
            ? appLocalized("Finishes the review and keeps every photo in this cluster")
            : appLocalized("Finishes the review and keeps the photos you did not select")
    }

    /// Two labelled sections instead of one flat list: acting on the selection
    /// and changing how the grid looks are different jobs, and the column
    /// options stay folded into a submenu so they never outnumber the actions.
    private var overflowMenu: some View {
        Menu {
            if viewModel.isActionBarVisible {
                Section(appLocalized("Selection")) {
                    Button {
                        viewModel.selectAllExceptBest()
                    } label: {
                        Label(appLocalized("Select All Except Best"), systemImage: "checkmark.circle")
                    }

                    if viewModel.selectedCount > 0 {
                        Button {
                            viewModel.clearSelection()
                        } label: {
                            Label(appLocalized("Clear Selection"), systemImage: "xmark.circle")
                        }
                    }
                }
            }

            Section(appLocalized("View")) {
                Picker(selection: selectedGridColumnBinding) {
                    ForEach(gridLayoutPolicy.columnCounts, id: \.self) { count in
                        Text(String(format: appLocalized("%d Columns"), count)).tag(count)
                    }
                } label: {
                    Label(appLocalized("Columns"), systemImage: "square.grid.3x2")
                }
                .pickerStyle(.menu)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(Text(appLocalized("More Options")))
        .accessibilityHint(Text(appLocalized("Selection shortcuts and grid layout")))
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
                ALICleanupProgressView(
                    selectedCount: viewModel.selectedCount,
                    estimatedSavingsText: viewModel.estimatedSavingsText,
                    isExecuting: viewModel.isDeleting
                )
            } else {
                if viewModel.hasAssets {
                    ClusterReviewSummaryCard(
                        assetCount: viewModel.assetCount,
                        bestShotLabel: viewModel.bestShotLabel,
                        selectedCount: viewModel.selectedCount,
                        estimatedSavingsText: viewModel.estimatedSavingsText,
                        maximumEstimatedSavingsText: viewModel.maximumEstimatedSavingsText,
                        reviewStatus: viewModel.reviewStatus,
                        isReviewConfirmed: viewModel.isReviewConfirmed,
                        aliReactionCue: viewModel.currentALIReaction,
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
                        Label(appLocalized("No Photos Available"), systemImage: "photo")
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
                                isBestShot: viewModel.isBestShot(asset.localIdentifier),
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
                }
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.small)
        .padding(.bottom, Spacing.medium)
    }
}

private extension ClusterDetailsView {
    var gridLayoutPolicy: AdaptivePhotoGridLayoutPolicy {
        horizontalSizeClass == .regular ? .regular : .compact
    }

    var selectedGridColumnCount: Int {
        horizontalSizeClass == .regular ? regularGridColumns : compactGridColumns
    }

    var selectedGridColumnBinding: Binding<Int> {
        Binding(
            get: { selectedGridColumnCount },
            set: { newValue in
                guard gridLayoutPolicy.columnCounts.contains(newValue) else { return }
                if horizontalSizeClass == .regular {
                    regularGridColumns = newValue
                } else {
                    compactGridColumns = newValue
                }
            }
        )
    }

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
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onOpenOriginal: () -> Void
    var onMakeBestShot: (() -> Void)?

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
                            Text(appLocalized("Best Shot"))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "star.fill")
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
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
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
                    Button(appLocalized("Make Best Shot"), action: onMakeBestShot)
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
            if let onMakeBestShot, !isBestShot {
                Button {
                    onMakeBestShot()
                } label: {
                    Label {
                        Text(appLocalized("Make Best Shot"))
                    } icon: {
                        Image(systemName: "star")
                    }
                }
            }

            Button {
                showingMetadata = true
            } label: {
                Label {
                    Text(appLocalized("Show Info"))
                } icon: {
                    Image(systemName: "info.circle")
                }
            }
            
            Button {
                onOpenOriginal()
            } label: {
                Label {
                    Text(appLocalized("Open Original"))
                } icon: {
                    Image(systemName: "arrow.up.right.square")
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

    private var accessibilityLabel: String {
        if isBestShot {
            return appLocalized("Best Shot")
        }
        if isSelected {
            return appLocalized("Selected for cleanup review")
        }
        return appLocalized("Not selected")
    }

    private var accessibilityValue: String {
        if isBestShot {
            return appLocalized("Best Shot")
        }
        return isSelected ? appLocalized("Selected") : appLocalized("Not selected")
    }

    private var accessibilityHint: String {
        if isBestShot {
            return appLocalized("This photo is kept as the best shot. Long press another photo to make it the best shot instead.")
        }
        return isSelected
            ? appLocalized("Double tap to remove this photo from cleanup selection")
            : appLocalized("Double tap to select this photo for cleanup")
    }
}

// MARK: - Fullscreen Photo View
private struct FullscreenPhotoPagerView: View {
    let assets: [PHAsset]
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(assets: [PHAsset], selectedIndex: Int) {
        self.assets = assets
        self._currentIndex = State(initialValue: selectedIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(assets.indices, id: \.self) { index in
                    FullscreenZoomablePhotoView(asset: assets[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding()
            }
            .accessibilityLabel(Text(appLocalized("Close")))
        }
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
                        Text(appLocalized("Resolution"))
                    }

                    LabeledContent {
                        Text(formattedMegapixels)
                    } label: {
                        Text(appLocalized("Megapixels"))
                    }

                    LabeledContent {
                        Text(photoType)
                    } label: {
                        Text(appLocalized("Photo Type"))
                    }

                    LabeledContent {
                        Text(metadata.isFavorite ? appLocalized("Yes") : appLocalized("No"))
                    } label: {
                        Text(appLocalized("Favorite"))
                    }
                } header: {
                    Text(appLocalized("Details"))
                }

                if metadata.creationDate != nil || metadata.modificationDate != nil {
                    Section {
                        if metadata.creationDate != nil {
                            LabeledContent {
                                Text(metadata.formattedCreationDate)
                            } label: {
                                Text(appLocalized("Created"))
                            }
                        }

                        if let modified = metadata.formattedModificationDate {
                            LabeledContent {
                                Text(modified)
                            } label: {
                                Text(appLocalized("Modified"))
                            }
                        }
                    } header: {
                        Text(appLocalized("Dates"))
                    }
                }

                if let location = metadata.location {
                    PhotoInfoLocationSection(location: location)
                }
            }
            .navigationTitle(Text(appLocalized("Photo Info")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text(appLocalized("Done"))
                    }
                }
            }
        }
    }

    private var formattedMegapixels: String {
        let value = metadata.megapixelCount.formatted(
            .number.precision(.fractionLength(0...1))
        )
        return String(format: appLocalized("%@ MP"), value)
    }

    private var photoType: String {
        guard !metadata.photoTraits.isEmpty else {
            return appLocalized("Photo")
        }

        return metadata.photoTraits.map { trait in
            switch trait {
            case .screenshot:
                appLocalized("Screenshot")
            case .panorama:
                appLocalized("Panorama")
            case .livePhoto:
                appLocalized("Live Photo")
            case .hdr:
                appLocalized("HDR")
            case .depthEffect:
                appLocalized("Depth Effect")
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
                    .accessibilityLabel(Text(appLocalized("Photo preview")))
            } else if isLoading {
                ProgressView()
                    .accessibilityLabel(Text(appLocalized("Loading photo preview")))
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(appLocalized("Photo preview unavailable")))
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
                Marker(appLocalized("Photo location"), coordinate: coordinate)
            }
            .frame(height: 160)
            .listRowInsets(EdgeInsets())
            .accessibilityLabel(Text(appLocalized("Map showing where the photo was taken")))

            Button {
                openInMaps()
            } label: {
                Label(appLocalized("Open in Maps"), systemImage: "map")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityHint(Text(appLocalized("Opens the photo location in Maps")))
        } header: {
            Text(appLocalized("Location"))
        }
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = appLocalized("Photo location")
        mapItem.openInMaps()
    }
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
            Label(appLocalized("Similar Photos"), systemImage: "photo.stack")
        } description: {
            Text(appLocalized("Cluster details are available on iOS."))
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
#Preview {
    RoutedNavigationStack {
        ClusterDetailsView(cluster: .mock)
    }
}
