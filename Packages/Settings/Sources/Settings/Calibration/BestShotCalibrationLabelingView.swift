#if DEBUG
import Core
import DesignSystem
import Photos
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Developer-only tool for building a Best Shot calibration corpus: walks
/// real clusters, lets a human pick the Best Shot and an optional scene
/// category, then exports the accumulated labels for the offline harness.
///
/// This screen is never part of a shipping build (see `#if DEBUG` above), so
/// its copy is left as plain English literals rather than routed through the
/// localized `.xcstrings` catalogs — matching how `SettingsView.debugSection`
/// handles its own developer-only strings.
///
/// IMPORTANT: this screen must never surface the app's own Best Shot pick
/// (e.g. `PhotoQualityAnalyzing`'s ranking). The whole point of this corpus
/// is an independent human label; showing the ranker's recommendation first
/// would anchor the labeller and quietly bias the ground truth this corpus
/// is meant to calibrate against. Do not add it back.
public struct BestShotCalibrationLabelingView: View {
    private enum Layout {
        /// Share of the container height given to the large preview, leaving
        /// the rest for the filmstrip and the pinned bottom bar.
        static let previewHeightFraction: CGFloat = 0.5
        static let filmstripTileSide: CGFloat = 64
        static let filmstripHeight: CGFloat = 76
    }

    @State private var viewModel: BestShotCalibrationLabelingViewModel
    @State private var selectedBestShotID: String?
    @State private var selectedCategory: BestShotCalibrationCategory?
    @State private var focusedAssetID: String?
    @State private var isResetConfirmationPresented = false
    @State private var exportedFileURL: URL?
    @State private var exportErrorMessage: String?

    public init(viewModel: BestShotCalibrationLabelingViewModel = BestShotCalibrationLabelingViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        content
            .navigationTitle("Calibration")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let exportedFileURL {
                        ShareLink(item: exportedFileURL) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            prepareExport()
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        isResetConfirmationPresented = true
                    } label: {
                        Label("Reset corpus", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .task {
                await viewModel.loadNextCluster()
            }
            .onChange(of: viewModel.currentCandidateAssets.map(\.localIdentifier)) { _, identifiers in
                focusedAssetID = identifiers.first
            }
            .confirmationDialog(
                "Reset corpus?",
                isPresented: $isResetConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Reset corpus", role: .destructive) {
                    viewModel.reset()
                    resetSelection()
                    exportedFileURL = nil
                    Task { await viewModel.loadNextCluster() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently discards every label recorded in this session. It cannot be undone.")
            }
            .alert(
                "Couldn't export corpus",
                isPresented: Binding(
                    get: { exportErrorMessage != nil },
                    set: { isPresented in if !isPresented { exportErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { exportErrorMessage = nil }
            } message: {
                Text(exportErrorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            progressHeader

            if viewModel.isLoadingCluster || viewModel.isScoring {
                Spacer()
                ProgressView()
                Spacer()
            } else if let message = viewModel.loadErrorMessage {
                Spacer()
                ContentUnavailableView {
                    Label("Couldn't load clusters", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
                Spacer()
            } else if viewModel.isFinished {
                Spacer()
                ContentUnavailableView {
                    Label("No more clusters", systemImage: "checkmark.circle")
                } description: {
                    Text("Every eligible cluster has been labelled.")
                }
                Spacer()
            } else if let cluster = viewModel.currentCluster {
                labelingForm(cluster: cluster)
            }
        }
    }

    private var progressHeader: some View {
        HStack {
            Text("\(viewModel.labelledCount) labelled")
                .font(.appFootnote)
                .foregroundStyle(.secondary)
            Spacer()
            if let position = candidatePositionText {
                Text(position)
                    .font(.appFootnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.small)
    }

    /// "2 of 5" for the candidate currently focused in the large preview.
    private var candidatePositionText: String? {
        let assets = viewModel.currentCandidateAssets
        guard !assets.isEmpty,
              let focusedAssetID,
              let index = assets.firstIndex(where: { $0.localIdentifier == focusedAssetID })
        else { return nil }
        return "\(index + 1) of \(assets.count)"
    }

    private func labelingForm(cluster: PhotoCluster) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                largePreview(cluster: cluster, containerHeight: proxy.size.height)

                filmstrip

                Spacer(minLength: 0)

                bottomBar(cluster: cluster)
            }
        }
    }

    // MARK: - Large preview

    private func largePreview(cluster: PhotoCluster, containerHeight: CGFloat) -> some View {
        let assets = viewModel.currentCandidateAssets
        return TabView(selection: focusedAssetIDBinding(assets: assets)) {
            ForEach(assets, id: \.localIdentifier) { asset in
                CalibrationPreviewTile(asset: asset)
                    .padding(.horizontal, Spacing.medium)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedBestShotID = asset.localIdentifier
                    }
                    .tag(asset.localIdentifier as String?)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: containerHeight * Layout.previewHeightFraction)
        .animation(.default, value: focusedAssetID)
    }

    private func focusedAssetIDBinding(assets: [PHAsset]) -> Binding<String?> {
        Binding(
            get: { focusedAssetID ?? assets.first?.localIdentifier },
            set: { focusedAssetID = $0 }
        )
    }

    // MARK: - Filmstrip

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xSmall) {
                ForEach(viewModel.currentCandidateAssets, id: \.localIdentifier) { asset in
                    CalibrationFilmstripTile(
                        asset: asset,
                        isFocused: focusedAssetID == asset.localIdentifier,
                        isBestShot: selectedBestShotID == asset.localIdentifier
                    )
                    .frame(width: Layout.filmstripTileSide, height: Layout.filmstripTileSide)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            focusedAssetID = asset.localIdentifier
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.medium)
        }
        .frame(height: Layout.filmstripHeight)
        .padding(.vertical, Spacing.small)
    }

    // MARK: - Bottom bar

    private func bottomBar(cluster: PhotoCluster) -> some View {
        VStack(spacing: Spacing.medium) {
            categoryPicker

            markBestShotButton

            Button {
                guard let selectedBestShotID else { return }
                viewModel.recordLabel(
                    clusterID: cluster.id,
                    bestShotAssetID: selectedBestShotID,
                    category: selectedCategory
                )
                resetSelection()
                // A prepared export is a snapshot of the corpus as it was;
                // once a new label lands it would share a stale file.
                exportedFileURL = nil
                Task { await viewModel.loadNextCluster() }
            } label: {
                Text("Save & Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedBestShotID == nil)
        }
        .padding(Spacing.medium)
        .background(.bar)
    }

    private var markBestShotButton: some View {
        let isMarked = selectedBestShotID != nil && selectedBestShotID == focusedAssetID
        return Button {
            guard let focusedAssetID else { return }
            selectedBestShotID = focusedAssetID
        } label: {
            Label(
                isMarked ? "Best Shot" : "Mark as Best Shot",
                systemImage: isMarked ? "star.fill" : "star"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(isMarked ? Color.accent : nil)
        .disabled(focusedAssetID == nil)
    }

    private var categoryPicker: some View {
        HStack {
            Text("Category")
            Spacer()
            Picker("Category", selection: $selectedCategory) {
                Text("None").tag(BestShotCalibrationCategory?.none)
                ForEach(BestShotCalibrationCategory.allCases, id: \.self) { category in
                    Text(category.rawValue.capitalized).tag(BestShotCalibrationCategory?.some(category))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func resetSelection() {
        selectedBestShotID = nil
        selectedCategory = nil
    }

    private func prepareExport() {
        do {
            exportedFileURL = try viewModel.exportedCorpusFileURL()
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}

/// The large, swipeable preview of one candidate. Shown `scaledToFit` so
/// nothing is cropped away — a crop could hide exactly the blur or closed
/// eyes the labeller is judging.
///
/// Uses the overlay pattern deliberately: `Color.clear` is what reports size
/// to the parent, and the image is only ever drawn into that reserved frame.
/// An `Image(...).resizable()` placed as a sibling in a `ZStack` instead
/// reports its own intrinsic size upward and inflates the container —
/// `.clipped()` only limits drawing, not the size the view reports.
private struct CalibrationPreviewTile: View {
    private enum Layout {
        /// Bounded, not `PHImageManagerMaximumSize` — `PHAsset.loadImage`
        /// explicitly rejects that sentinel (it means "uncached original",
        /// not "large"), so the preview needs a real target size. Large
        /// enough that scaling up to near-full width on any device stays
        /// sharp, but still a fraction of most originals.
        static let targetSide: CGFloat = 1200
    }

    let asset: PHAsset

#if canImport(UIKit)
    @State private var image: UIImage?
#endif

    var body: some View {
        Color.clear
            .overlay {
#if canImport(UIKit)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
#endif
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
#if canImport(UIKit)
            .task(id: asset.localIdentifier) {
                image = try? await asset.loadImage(
                    targetSize: CGSize(width: Layout.targetSide, height: Layout.targetSide)
                )
            }
#endif
    }
}

/// One filmstrip tile: a square thumbnail. The focused candidate gets a
/// clear selection ring; the candidate currently marked Best Shot gets a
/// filled star badge in its corner, independent of focus.
private struct CalibrationFilmstripTile: View {
    private enum Layout {
        static let ringWidth: CGFloat = 3
        static let badgePadding: CGFloat = 2
        static let targetSide: CGFloat = 200
    }

    let asset: PHAsset
    let isFocused: Bool
    let isBestShot: Bool

#if canImport(UIKit)
    @State private var image: UIImage?
#endif

    var body: some View {
        Color.secondary.opacity(ColorOpacity.placeholderFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
#if canImport(UIKit)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
#endif
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.small)
                    .stroke(isFocused ? Color.accent : Color.clear, lineWidth: Layout.ringWidth)
            )
            .overlay(alignment: .topTrailing) {
                if isBestShot {
                    Image(systemName: "star.circle.fill")
                        .foregroundStyle(Color.accent, .white)
                        .padding(Layout.badgePadding)
                }
            }
#if canImport(UIKit)
            .task(id: asset.localIdentifier) {
                image = try? await asset.loadImage(
                    targetSize: CGSize(width: Layout.targetSide, height: Layout.targetSide)
                )
            }
#endif
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        BestShotCalibrationLabelingView()
    }
}
#endif
