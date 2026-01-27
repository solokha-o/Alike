import SwiftUI
import Core
import DesignSystem
import Details
import Photos

/// Scanner screen with analysis and results
public struct ScannerView: View {
    @State private var viewModel: ScannerViewModel
    @Binding var gridColumns: Int
    @Binding var sensitivity: SensitivityLevel
    
    public init(
        gridColumns: Binding<Int>,
        sensitivity: Binding<SensitivityLevel>
    ) {
        self._gridColumns = gridColumns
        self._sensitivity = sensitivity
        self._viewModel = State(initialValue: ScannerViewModel(
            gridColumns: gridColumns.wrappedValue,
            sensitivity: sensitivity.wrappedValue
        ))
    }
    
    public var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle:
                    idleView
                case .scanning(let progress):
                    scanningView(progress: progress)
                case .results(let clusters):
                    resultsView(clusters: clusters)
                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await viewModel.loadCachedResults()
            
            // Check if gallery changed
            if await viewModel.checkForGalleryChanges() {
                // Show rescan suggestion (simplified for MVP)
            }
        }
        .onChange(of: gridColumns) { _, newValue in
            viewModel.gridColumns = newValue
        }
    }
    
    // MARK: - Idle View
    private var idleView: some View {
        VStack(spacing: Spacing.xLarge) {
            Spacer()
            
            Image(systemName: "photo.stack")
                .font(.system(size: 80))
                .foregroundColor(.accent)
            
            Text("Ready to Scan")
                .font(.title)
                .foregroundColor(.primary)
            
            Text("Tap the button below to analyze your photo library")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xLarge)
            
            Spacer()
            
            PrimaryButton("Start Scanning", icon: "sparkles") {
                Task {
                    await viewModel.startScanning()
                }
            }
            .padding(.horizontal, Spacing.large)
            .padding(.bottom, Spacing.xLarge)
        }
    }
    
    // MARK: - Scanning View
    private func scanningView(progress: Double) -> some View {
        VStack(spacing: Spacing.xxLarge) {
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(Color.accent.opacity(0.2), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: progress)
                
                Text("\(Int(progress * 100))%")
                    .font(.title.bold())
                    .foregroundColor(.accent)
            }
            
            Text("Analyzing Photos...")
                .font(.title2)
                .foregroundColor(.primary)
            
            Text("Finding visually similar images")
                .font(.body)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Results View
    private func resultsView(clusters: [PhotoCluster]) -> some View {
        ScrollView {
            if clusters.isEmpty {
                ContentUnavailableView(
                    "No Similar Photos Found",
                    systemImage: "photo.stack",
                    description: Text("Try adjusting sensitivity in Settings")
                )
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.small), count: gridColumns), spacing: Spacing.small) {
                    ForEach(clusters) { cluster in
                        ClusterCard(cluster: cluster)
                    }
                }
                .padding(Spacing.medium)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await viewModel.startScanning()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .scaleOnPress()
            }
        }
        .sensoryFeedback(.success, trigger: clusters.count)
    }
    
    // MARK: - Error View
    private func errorView(message: String) -> some View {
        ContentUnavailableView(
            "Scan Failed",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }
}

// MARK: - Cluster Card
struct ClusterCard: View {
    let cluster: PhotoCluster
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        NavigationLink {
            ClusterDetailsView(cluster: cluster)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 150)
                        .overlay {
                            ProgressView()
                        }
                }
                
                // Count badge
                Text("\(cluster.count)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.small)
                    .padding(.vertical, Spacing.xxSmall)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(Spacing.xSmall)
            }
            .cornerRadius(CornerRadius.medium)
            .subtleShadow()
        }
        .task {
            if let asset = cluster.thumbnail {
                thumbnailImage = try? await asset.loadImage()
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ScannerView(
        gridColumns: .constant(3),
        sensitivity: .constant(.medium)
    )
}
