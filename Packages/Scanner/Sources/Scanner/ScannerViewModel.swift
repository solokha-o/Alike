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
    public private(set) var reviewStates: [UUID: ClusterReviewState] = [:]
    
    private let analysisService: PhotoAnalysisService
    private let repository: PhotoClusterRepository
    private let reviewRepository: ClusterReviewStateRepository
    public var sensitivity: SensitivityLevel
    
    public init(
        gridColumns: Int = 3,
        sensitivity: SensitivityLevel = .medium,
        analysisService: PhotoAnalysisService? = nil,
        repository: PhotoClusterRepository = CoreDataPhotoClusterRepository(),
        reviewRepository: ClusterReviewStateRepository = FileClusterReviewStateRepository()
    ) {
        self.gridColumns = gridColumns
        self.sensitivity = sensitivity
        self.repository = repository
        self.reviewRepository = reviewRepository
        
        if let analysisService {
            self.analysisService = analysisService
        } else if let featurePrintRepository = repository as? PhotoFeaturePrintRepository {
            self.analysisService = PhotoAnalysisServiceImpl(featurePrintRepository: featurePrintRepository)
        } else {
            self.analysisService = PhotoAnalysisServiceImpl()
        }
    }
    
    public func loadCachedResults() async {
        do {
            let clusters = try await repository.loadClusters()
            if !clusters.isEmpty {
                let sorted = sortedClusters(from: clusters)
                if case .results(let existing) = state, existing == sorted {
                    return
                }
                AppLog.ui.debug("\(AppLog.tag(.cache, "Loaded cached clusters: \(sorted.count)"))")
                state = .results(sorted)
                await loadReviewStates()
            }
        } catch {
            AppLog.ui.error("\(AppLog.tag(.error, "Failed to load cached results: \(error.localizedDescription)"))")
        }
    }
    
    public func startScanning() async {
        AppLog.scan.info("\(AppLog.tag(.start, "Scan started"))")
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
            AppLog.scan.info("\(AppLog.tag(.finish, "Scan finished with clusters: \(sorted.count)"))")
            state = .results(sorted)
            await loadReviewStates()
        } catch {
            AppLog.scan.error("\(AppLog.tag(.error, "Scan failed: \(error.localizedDescription)"))")
            state = .error(error.localizedDescription)
        }
    }
    
    public func checkForGalleryChanges() async -> Bool {
        await repository.hasGalleryChanged()
    }

    public func loadReviewStates() async {
        do {
            reviewStates = try await reviewRepository.loadAllReviewStates()
        } catch {
            AppLog.ui.error("\(AppLog.tag(.error, "Failed to load review states: \(error.localizedDescription)"))")
            reviewStates = [:]
        }
    }

    public func reviewState(for clusterID: UUID) -> ClusterReviewState? {
        reviewStates[clusterID]
    }

    public func reviewStatus(for clusterID: UUID) -> ClusterReviewStatus {
        reviewStates[clusterID]?.status ?? .notReviewed
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
