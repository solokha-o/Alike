import SwiftUI
import Core
import Storage
import PhotoAnalysis

@MainActor
@Observable
public final class ScannerViewModel {
    public enum State: Equatable {
        case idle
        case scanning(progress: Double)
        case results([PhotoCluster])
        case error(String)
    }
    
    public var state: State = .idle
    public var gridColumns: Int
    
    private let analysisService: PhotoAnalysisService
    private let repository: PhotoClusterRepository
    public var sensitivity: SensitivityLevel
    
    public init(
        gridColumns: Int = 3,
        sensitivity: SensitivityLevel = .medium,
        analysisService: PhotoAnalysisService = PhotoAnalysisServiceImpl(),
        repository: PhotoClusterRepository = CoreDataPhotoClusterRepository()
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
                let sorted = sortedClusters(from: clusters)
                if case .results(let existing) = state, existing == sorted {
                    return
                }
                state = .results(sorted)
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
            
            let sorted = sortedClusters(from: clusters)
            if case .results(let existing) = state, existing == sorted {
                return
            }
            state = .results(sorted)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
    
    public func checkForGalleryChanges() async -> Bool {
        await repository.hasGalleryChanged()
    }

    public func sortedClusters(from clusters: [PhotoCluster]) -> [PhotoCluster] {
        clusters.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            if $0.count != $1.count {
                return $0.count > $1.count
            }
            if $0.averageSimilarity != $1.averageSimilarity {
                return $0.averageSimilarity > $1.averageSimilarity
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
