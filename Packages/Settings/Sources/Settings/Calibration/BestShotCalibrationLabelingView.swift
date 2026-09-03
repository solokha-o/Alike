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
public struct BestShotCalibrationLabelingView: View {
    @State private var viewModel: BestShotCalibrationLabelingViewModel
    @State private var selectedBestShotID: String?
    @State private var selectedCategory: BestShotCalibrationCategory?
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
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.small)
    }

    private func labelingForm(cluster: PhotoCluster) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                candidateGrid

                categoryPicker

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
        }
    }

    private var candidateGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xSmall), count: 3),
            spacing: Spacing.xSmall
        ) {
            ForEach(viewModel.currentCandidateAssets, id: \.localIdentifier) { asset in
                CalibrationCandidateThumbnail(
                    asset: asset,
                    isSelected: selectedBestShotID == asset.localIdentifier
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedBestShotID = asset.localIdentifier
                }
            }
        }
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

/// A single candidate tile: the photo, and a highlighted ring once selected as
/// the human Best Shot.
private struct CalibrationCandidateThumbnail: View {
    let asset: PHAsset
    let isSelected: Bool

#if canImport(UIKit)
    @State private var image: UIImage?
#endif

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
#if canImport(UIKit)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            }
#endif
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.small)
                .stroke(isSelected ? Color.accent : Color.clear, lineWidth: 3)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "star.circle.fill")
                    .foregroundStyle(Color.accent, .white)
                    .padding(Spacing.xxSmall)
            }
        }
#if canImport(UIKit)
        .task(id: asset.localIdentifier) {
            image = try? await asset.loadImage(targetSize: CGSize(width: 300, height: 300))
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
