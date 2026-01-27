import SwiftUI
import Core
import Storage
import PhotoAnalysis

@MainActor
@Observable
public final class ScannerViewModel {
    public enum State {
        case idle
        case scanning(progress: Double)
        case results([PhotoCluster])
        case error(String)
    }
    
    public var state: State = .idle
    public var gridColumns: Int
    
    private let analysisService: PhotoAnalysisServiceImpl
    private let repository: CoreDataPhotoClusterRepository
    private let sensitivity: SensitivityLevel
    
    public init(
        gridColumns: Int = 3,
        sensitivity: SensitivityLevel = .medium,
        analysisService: PhotoAnalysisServiceImpl = PhotoAnalysisServiceImpl(),
        repository: CoreDataPhotoClusterRepository = CoreDataPhotoClusterRepository()
    ) {
        self.gridColumns = gridColumns
        self.sensitivity = sensitivity
        self.analysisService = analysisService
        self.repository = repository
    }
    
    public func loadCachedResults() async {
        do {
            let clusters = try await repository.loadClusters()
            if !clusters.isEmpty {
                state = .results(clusters)
            }
        } catch {
            print("Failed to load cached results: \(error)")
        }
    }
    
    public func startScanning() async {
        state = .scanning(progress: 0.0)
        
        do {
            let clusters = try await analysisService.analyzePhotoLibrary(
                sensitivity: sensitivity.threshold
            ) { progress in
                Task { @MainActor in
                    self.state = .scanning(progress: progress)
                }
            }
            
            // Save results
            try await repository.saveClusters(clusters)
            try await repository.updateLastScanDate(Date())
            
            state = .results(clusters)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    public func checkForGalleryChanges() async -> Bool {
        await repository.hasGalleryChanged()
    }
}
