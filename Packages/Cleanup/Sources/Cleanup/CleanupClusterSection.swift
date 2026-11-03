import SwiftUI
import Photos
import Core
import DesignSystem
import PhotoAnalysis

struct CleanupClusterSection: View {
    let title: String
    let subtitle: String
    let clusters: [IdentifiedCluster]
    let gridColumns: Int
    let workspace: CleanupWorkspaceModel
    let onOpen: (PhotoCluster) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack {
                Text(title)
                    .font(.appHeadline)
                Text(clusters.count, format: .alikeNumber)
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .cleanupGlassBadge()
                Spacer()
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Spacing.small),
                    count: CleanupPresentation.gridColumnCount(gridColumns)
                ),
                spacing: Spacing.small
            ) {
                ForEach(clusters) { identified in
                    let cluster = identified.cluster
                    CleanupClusterCard(
                        cluster: cluster,
                        previewAsset: cluster.bestShotAsset(
                            preferring: workspace.reviewState(for: cluster.id)?.bestShotLocalIdentifier
                        ),
                        status: workspace.reviewStatus(for: cluster.id),
                        resurfacing: workspace.resurfacingState(for: cluster.id)
                    ) {
                        onOpen(cluster)
                    }
                    .id(identified.id)
                }
            }
            .scrollTargetLayout()
        }
    }
}

private struct CleanupClusterCard: View {
    let cluster: PhotoCluster
    /// The cluster's keeper, so the card previews the photo the review is
    /// keeping instead of whichever asset clustering happened to emit first.
    let previewAsset: PHAsset?
    let status: ClusterReviewStatus
    let resurfacing: ClusterResurfacingState?
    let open: () -> Void

    @Environment(\.colorScheme) private var colorScheme

#if os(iOS)
    @State private var image: UIImage?
    @State private var imageLoadState = PhotoImageLoadState()
    @State private var imageLoadAttempt = 0
#endif

    var body: some View {
        ZStack {
            Button(action: open) {
                ZStack(alignment: .bottomTrailing) {
                    thumbnail
                    Text(cluster.count, format: .alikeNumber)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 28, height: 28)
                        .cleanupGlassBadge(.circle)
                        .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    Label(statusTitle, systemImage: statusIconName)
                        .font(.caption2.bold())
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(5)
                        .cleanupGlassBadge()
                        .padding(5)
                }
                .overlay(alignment: .bottomLeading) {
                    if let resurfacing, resurfacing != .unchanged {
                        Image(systemName: resurfacing == .new ? "sparkles" : "arrow.triangle.2.circlepath")
                            .padding(6)
                            .cleanupGlassBadge(.circle)
                            .padding(5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(clusterAccessibilityLabel))
            .accessibilityHint(Text(CleanupL10n.Main.openThisClusterReviewPhotos))
#if os(iOS)
            if imageLoadState.phase == .failed {
                PhotoLoadFailureView {
                    imageLoadAttempt += 1
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.small))
            }
#endif
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
#if os(iOS)
        PhotoThumbnailAspectRatioLayout(aspectRatio: 1) {
            ZStack {
                placeholder

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .task(id: imageLoadTaskID) {
            await loadThumbnail()
        }
#else
        PhotoThumbnailAspectRatioLayout(aspectRatio: 1) {
            placeholder
        }
        .frame(maxWidth: .infinity)
#endif
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.secondary.opacity(ColorOpacity.placeholderFill))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }

#if os(iOS)
    private var imageLoadTaskID: String {
        "\(previewAsset?.localIdentifier ?? "missing")#\(imageLoadAttempt)"
    }

    @MainActor
    private func loadThumbnail() async {
        guard let asset = previewAsset else { return }

        image = nil
        let generation = imageLoadState.begin()
        do {
            guard let loadedImage = try await asset.loadImage(
                targetSize: CGSize(width: 1_000, height: 1_000)
            ) else {
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
#endif

    private var statusTitle: String {
        CleanupPresentation.clusterStatusTitle(status)
    }

    private var statusIconName: String {
        CleanupPresentation.clusterStatusIconName(status)
    }

    private var statusColor: Color {
        switch status {
        case .notReviewed:
            colorScheme == .dark ? .primary.opacity(0.85) : .secondary
        case .needsReReview:
            .statusNeedsReview
        case .inReview:
            .statusInReview
        case .reviewed:
            .statusReviewed
        }
    }

    private var clusterAccessibilityLabel: String {
        CleanupPresentation.clusterAccessibilityLabel(
            photoCount: cluster.count,
            status: status,
            resurfacing: resurfacing
        )
    }
}
