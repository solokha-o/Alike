import SwiftUI
import Photos
import Core
import DesignSystem

/// Details screen showing all photos in a cluster
public struct ClusterDetailsView: View {
    let cluster: PhotoCluster
    @State private var gridColumns: Int = 3
    @Environment(\.dismiss) private var dismiss
    
    public init(cluster: PhotoCluster) {
        self.cluster = cluster
    }
    
    public var body: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.small), count: gridColumns),
                spacing: Spacing.small
            ) {
                ForEach(cluster.assets, id: \.localIdentifier) { asset in
                    PhotoThumbnail(asset: asset)
                }
            }
            .padding(Spacing.medium)
        }
        .navigationTitle("Similar Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Columns", selection: $gridColumns) {
                        ForEach(2...4, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                } label: {
                    Image(systemName: "square.grid.3x2")
                }
            }
        }
    }
}

// MARK: - Photo Thumbnail
struct PhotoThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var showingMetadata = false
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 120)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .cornerRadius(CornerRadius.small)
        .contextMenu {
            Button {
                showingMetadata = true
            } label: {
                Label("Show Info", systemImage: "info.circle")
            }
            
            Button {
                // Open in Photos app
                if let url = URL(string: "photos-redirect://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Original", systemImage: "arrow.up.right.square")
            }
        }
        .sheet(isPresented: $showingMetadata) {
            MetadataView(metadata: asset.displayMetadata)
                .presentationDetents([.medium])
        }
        .task {
            image = try? await asset.loadImage(targetSize: CGSize(width: 300, height: 300))
        }
    }
}

// MARK: - Metadata View
struct MetadataView: View {
    let metadata: AssetMetadata
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    LabeledContent("Resolution", value: metadata.resolution)
                    LabeledContent("Created", value: metadata.formattedCreationDate)
                    LabeledContent("Favorite", value: metadata.isFavorite ? "Yes" : "No")
                }
            }
            .navigationTitle("Photo Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        ClusterDetailsView(cluster: .mock)
    }
}
