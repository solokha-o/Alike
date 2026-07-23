import SwiftUI
import Photos
import MapKit
import Core
import DesignSystem
import Storage
import NavigationKit
import Purchases
import PurchasesUI

struct ClusterGridLayoutPolicy: Equatable {
    let columnCounts: ClosedRange<Int>
    let defaultColumnCount: Int

    static let compact = ClusterGridLayoutPolicy(columnCounts: 1...2, defaultColumnCount: 2)
    static let regular = ClusterGridLayoutPolicy(columnCounts: 2...5, defaultColumnCount: 4)
}

#if os(iOS)

/// Details screen showing all photos in a cluster
public struct ClusterDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let onReviewStateChanged: (() -> Void)?
    private let onCleanupCompleted: ((CleanupCompletionRecord) -> Void)?
    private let subscriptionStore: SubscriptionStore?

    @State private var viewModel: ClusterDetailsViewModel
    @State private var compactGridColumns = ClusterGridLayoutPolicy.compact.defaultColumnCount
    @State private var regularGridColumns = ClusterGridLayoutPolicy.regular.defaultColumnCount
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
        let displayedAssets = viewModel.displayedAssets
        let gridColumns = selectedGridColumnCount
        VStack(spacing: Spacing.small) {
            if !viewModel.isDeleting {
                ClusterReviewSummaryCard(
                    assetCount: viewModel.assetCount,
                    bestShotLabel: viewModel.bestShotLabel,
                    selectedCount: viewModel.selectedCount,
                    estimatedSavingsText: viewModel.estimatedSavingsText,
                    reviewStatus: viewModel.reviewStatus,
                    aliReactionCue: viewModel.currentALIReaction,
                    bestShotCelebrationCue: viewModel.bestShotCelebrationCue,
                    onBestShotCelebrationDismissed: viewModel.consumeBestShotCelebration
                )
            }

            if viewModel.isActionBarVisible && !viewModel.isDeleting {
                ClusterReviewActionBar(
                    onKeepBestOnly: viewModel.keepBestOnly,
                    onSelectAllExceptBest: viewModel.selectAllExceptBest,
                    onClearSelection: viewModel.clearSelection,
                    onDeleteSelected: requestDeleteConfirmation,
                    isDeleteActionVisible: viewModel.isDeleteActionVisible,
                    isDeleting: viewModel.isDeleting
                )
            }

            if viewModel.requiresPremiumForCurrentSelection && !viewModel.isDeleting {
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

            ScrollView {
                if viewModel.isDeleting {
                    ALICleanupProgressView(
                        selectedCount: viewModel.selectedCount,
                        estimatedSavingsText: viewModel.estimatedSavingsText,
                        isExecuting: viewModel.isDeleting
                    )
                    .padding(.bottom, Spacing.medium)
                } else if !viewModel.hasAssets {
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
                    .padding(.bottom, Spacing.medium)
                }
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.small)
        .padding(.bottom, Spacing.medium)
        .animation(viewModel.hasLoadedReviewState ? .appSmooth : nil, value: displayedAssets.map(\.localIdentifier))
        .animation(viewModel.hasLoadedReviewState ? .appInteractive : nil, value: viewModel.selectedAssetIDs)
        .animation(viewModel.hasLoadedReviewState ? .appInteractive : nil, value: viewModel.reviewStatus)
        .sensoryFeedback(.selection, trigger: viewModel.selectedAssetIDs.count)
        .sensoryFeedback(.success, trigger: viewModel.reviewStatus == .reviewed)
        .navigationTitle(Text(appLocalized("Similar Photos")))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isDeleting)
        .toolbar {
            if !viewModel.isDeleting {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker(selection: selectedGridColumnBinding) {
                            ForEach(gridLayoutPolicy.columnCounts, id: \.self) { count in
                                Text("\(count)").tag(count)
                            }
                        } label: {
                            Text(appLocalized("Columns"))
                        }
                    } label: {
                        Image(systemName: "square.grid.3x2")
                    }
                    .accessibilityLabel(Text(appLocalized("Grid Columns")))
                    .accessibilityHint(Text(appLocalized("Choose how many columns are used to display photos")))
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
        .onChange(of: viewModel.pendingCompletionRecord) { _, record in
            guard let record else { return }
            onCleanupCompleted?(record)
            dismiss()
        }
        .onDisappear {
            guard !viewModel.hasCompletedCleanup else { return }
            onReviewStateChanged?()
        }
        .interactiveDismissDisabled(viewModel.isDeleting)
    }
}

private extension ClusterDetailsView {
    var gridLayoutPolicy: ClusterGridLayoutPolicy {
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
}

private struct SelectedAsset: Identifiable {
    let asset: PHAsset
    let index: Int
    var id: String { asset.localIdentifier }
}

private struct ThumbnailAspectRatioLayout: Layout {
    let aspectRatio: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard aspectRatio > 0 else { return .zero }

        if let width = proposal.width, width.isFinite {
            return CGSize(width: width, height: width / aspectRatio)
        }
        if let height = proposal.height, height.isFinite {
            return CGSize(width: height * aspectRatio, height: height)
        }

        let fallback = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: fallback.width, height: fallback.width / aspectRatio)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        for subview in subviews {
            subview.place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(bounds.size)
            )
        }
    }
}

struct SelectablePhotoThumbnail: View {
    let asset: PHAsset
    let thumbnailAspectRatio: CGFloat
    let isBestShot: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onOpenOriginal: () -> Void

    @State private var image: UIImage?
    @State private var showingMetadata = false

    var body: some View {
        Button(action: onToggleSelection) {
            ThumbnailAspectRatioLayout(aspectRatio: thumbnailAspectRatio) {
                ZStack {
                    Color.secondary.opacity(ColorOpacity.placeholderFill)

                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
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
        .contentShape(.interaction, thumbnailShape)
        .contentShape(.contextMenuPreview, thumbnailShape)
        .contextMenu {
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
        .task {
            image = try? await asset.loadImage(targetSize: thumbnailTargetSize)
        }
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityHint(Text(accessibilityHint))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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

    private var contextMenuPreview: some View {
        ZStack {
            Color.secondary.opacity(ColorOpacity.placeholderFill)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
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
            return appLocalized("This photo is marked as the best shot and cannot be selected")
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
                    ZoomablePhotoView(asset: assets[index])
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

private struct ZoomablePhotoView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(zoomGesture)
                        .gesture(
                            panGesture(in: proxy.size),
                            including: scale > 1 ? .all : .subviews
                        )
                } else if isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .task(id: asset.localIdentifier) {
            defer { isLoading = false }
            image = try? await asset.loadImage(targetSize: PHImageManagerMaximumSize)
        }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                let newScale = scale * delta
                scale = min(max(newScale, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale <= minScale {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = minScale
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, in: size)
            }
            .onEnded { _ in
                guard scale > 1 else {
                    offset = .zero
                    lastOffset = .zero
                    return
                }
                lastOffset = offset
            }
    }

    private func clampedOffset(_ proposed: CGSize, in size: CGSize) -> CGSize {
        ZoomingHelpers.clampedOffset(proposed, in: size, scale: scale)
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
