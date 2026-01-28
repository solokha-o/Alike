@preconcurrency import Vision
import Photos
import Core
import CoreLocation

/// Service that performs clustering of photos based on similarity
public struct PhotoClusteringService: Sendable {
    struct Candidate {
        let featurePrint: VNFeaturePrintObservation
        let creationDate: Date?
        let location: CLLocation?
    }
    
    struct ClusterResult {
        let indices: [Int]
        let averageSimilarity: Float
    }
    
    private let distanceProvider: @Sendable (VNFeaturePrintObservation, VNFeaturePrintObservation) throws -> Float
    private let maxTimeInterval: TimeInterval
    private let maxLocationDistance: CLLocationDistance
    private let isPreFilterEnabled: Bool
    
    public init(enablePreFilter: Bool = true) {
        let visionService = VisionFeaturePrintService()
        self.distanceProvider = { observation1, observation2 in
            try visionService.computeDistance(between: observation1, and: observation2)
        }
        self.maxTimeInterval = 24 * 60 * 60
        self.maxLocationDistance = 1_000
        self.isPreFilterEnabled = enablePreFilter
    }
    
    init(
        distanceProvider: @escaping @Sendable (VNFeaturePrintObservation, VNFeaturePrintObservation) throws -> Float,
        maxTimeInterval: TimeInterval = 24 * 60 * 60,
        maxLocationDistance: CLLocationDistance = 1_000,
        enablePreFilter: Bool = true
    ) {
        self.distanceProvider = distanceProvider
        self.maxTimeInterval = maxTimeInterval
        self.maxLocationDistance = maxLocationDistance
        self.isPreFilterEnabled = enablePreFilter
    }
    
    /// Cluster photos based on similarity threshold
    public func clusterPhotos(
        _ photos: [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)],
        threshold: Float
    ) throws -> [PhotoCluster] {
        let candidates = photos.compactMap { item -> (asset: PHAsset, candidate: Candidate)? in
            guard let featurePrint = item.featurePrint else { return nil }
            return (
                item.asset,
                Candidate(
                    featurePrint: featurePrint,
                    creationDate: item.asset.creationDate,
                    location: item.asset.location
                )
            )
        }
        
        guard !candidates.isEmpty else { return [] }
        
        let results = try clusterCandidates(
            candidates.map { $0.candidate },
            threshold: threshold
        )
        
        return results.map { result in
            let assets = result.indices.map { candidates[$0].asset }
            return PhotoCluster(
                assets: assets,
                averageSimilarity: result.averageSimilarity
            )
        }
    }
    
    func clusterCandidates(
        _ candidates: [Candidate],
        threshold: Float
    ) throws -> [ClusterResult] {
        guard !candidates.isEmpty else { return [] }
        
        var clusters: [[Int]] = []
        var assigned: Set<Int> = []
        
        // Complete-link clustering: a photo can join a cluster only if it is
        // similar to every photo already in that cluster.
        for i in 0..<candidates.count {
            guard !assigned.contains(i) else { continue }
            
            var cluster = [i]
            assigned.insert(i)
            
            for j in (i + 1)..<candidates.count {
                guard !assigned.contains(j) else { continue }
                
                var isSimilarToAll = true
                for memberIndex in cluster {
                    guard passesPreFilter(
                        candidate1: candidates[memberIndex],
                        candidate2: candidates[j]
                    ) else {
                        isSimilarToAll = false
                        break
                    }
                    
                    do {
                        let distance = try distanceProvider(
                            candidates[memberIndex].featurePrint,
                            candidates[j].featurePrint
                        )
                        if distance > threshold {
                            isSimilarToAll = false
                            break
                        }
                    } catch {
                        isSimilarToAll = false
                        break
                    }
                }
                
                if isSimilarToAll {
                    cluster.append(j)
                    assigned.insert(j)
                }
            }
            
            if cluster.count > 1 {
                clusters.append(cluster)
            }
        }
        
        return clusters.map { indices in
            // Calculate average similarity (lower distance = higher similarity)
            var totalDistance: Float = 0.0
            var comparisonCount = 0
            
            for i in 0..<indices.count {
                for j in (i + 1)..<indices.count {
                    if let distance = try? distanceProvider(
                        candidates[indices[i]].featurePrint,
                        candidates[indices[j]].featurePrint
                    ) {
                        totalDistance += distance
                        comparisonCount += 1
                    }
                }
            }
            
            let averageSimilarity = comparisonCount > 0
                ? 1.0 - (totalDistance / Float(comparisonCount) / 100.0) // Normalize to 0-1
                : 0.0
            
            return ClusterResult(
                indices: indices,
                averageSimilarity: max(0.0, min(1.0, averageSimilarity))
            )
        }
    }
    
    private func passesPreFilter(candidate1: Candidate, candidate2: Candidate) -> Bool {
        guard isPreFilterEnabled else { return true }
        if let date1 = candidate1.creationDate, let date2 = candidate2.creationDate {
            if abs(date1.timeIntervalSince(date2)) > maxTimeInterval {
                return false
            }
        }
        
        if let location1 = candidate1.location, let location2 = candidate2.location {
            if location1.distance(from: location2) > maxLocationDistance {
                return false
            }
        }
        
        return true
    }
}
