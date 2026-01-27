import Vision
import Photos
import Core

/// Actor that performs clustering of photos based on similarity
public actor PhotoClusteringService: Sendable {
    private let visionService = VisionFeaturePrintService()
    
    public init() {}
    
    /// Cluster photos based on similarity threshold
    public func clusterPhotos(
        _ photos: [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)],
        threshold: Float
    ) async throws -> [PhotoCluster] {
        // Filter out photos without feature prints
        let validPhotos = photos.compactMap { item -> (PHAsset, VNFeaturePrintObservation)? in
            guard let featurePrint = item.featurePrint else { return nil }
            return (item.asset, featurePrint)
        }
        
        guard !validPhotos.isEmpty else { return [] }
        
        var clusters: [[Int]] = [] // Array of arrays of indices
        var assigned: Set<Int> = []
        
        // Iterate through each photo
        for i in 0..<validPhotos.count {
            guard !assigned.contains(i) else { continue }
            
            // Start a new cluster
            var cluster = [i]
            assigned.insert(i)
            
            let (_, featurePrint1) = validPhotos[i]
            
            // Find similar photos
            for j in (i+1)..<validPhotos.count {
                guard !assigned.contains(j) else { continue }
                
                let (_, featurePrint2) = validPhotos[j]
                
                do {
                    let distance = try visionService.computeDistance(
                        between: featurePrint1,
                        and: featurePrint2
                    )
                    
                    if distance <= threshold {
                        cluster.append(j)
                        assigned.insert(j)
                    }
                } catch {
                    // Skip comparison errors
                    continue
                }
            }
            
            // Only keep clusters with more than 1 photo
            if cluster.count > 1 {
                clusters.append(cluster)
            }
        }
        
        // Convert index clusters to PhotoCluster models
        return clusters.map { indices in
            let assets = indices.map { validPhotos[$0].0 }
            
            // Calculate average similarity (lower distance = higher similarity)
            var totalDistance: Float = 0.0
            var comparisonCount = 0
            
            for i in 0..<indices.count {
                for j in (i+1)..<indices.count {
                    if let distance = try? visionService.computeDistance(
                        between: validPhotos[indices[i]].1,
                        and: validPhotos[indices[j]].1
                    ) {
                        totalDistance += distance
                        comparisonCount += 1
                    }
                }
            }
            
            let averageSimilarity = comparisonCount > 0
                ? 1.0 - (totalDistance / Float(comparisonCount) / 100.0) // Normalize to 0-1
                : 0.0
            
            return PhotoCluster(
                assets: assets,
                averageSimilarity: max(0.0, min(1.0, averageSimilarity))
            )
        }
    }
}
