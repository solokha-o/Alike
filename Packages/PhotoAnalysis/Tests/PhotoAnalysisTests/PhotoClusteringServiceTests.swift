import XCTest
@preconcurrency import Vision
#if canImport(UIKit)
import UIKit
#endif
@testable import PhotoAnalysis

@MainActor
final class PhotoClusteringServiceTests: XCTestCase {
    var service: PhotoClusteringService!
    
    override func setUp() async throws {
        service = PhotoClusteringService(enablePreFilter: false)
    }
    
    override func tearDown() async throws {
        service = nil
    }
    
    // MARK: - Clustering Algorithm Tests
    
    func testClusterEmptyArray() async throws {
        // Given: Empty array
        let candidates: [PhotoClusteringService.Candidate] = []
        
        // When: Clustering
        let clusters = try service.clusterCandidates(candidates, threshold: 0.9)
        
        // Then: Should return empty array
        XCTAssertTrue(clusters.isEmpty, "Clustering empty array should return empty result")
    }
    
    func testClusterSinglePhoto() async throws {
        // Given: Single photo with mock PHAsset
        let featurePrint = try await makeFeaturePrint(color: .red)
        let candidates: [PhotoClusteringService.Candidate] = [
            .init(featurePrint: featurePrint, creationDate: nil, location: nil)
        ]
        
        // When: Clustering
        let clusters = try service.clusterCandidates(candidates, threshold: 0.9)
        
        // Then: Single photo should not form a cluster (clusters require > 1 photo)
        XCTAssertTrue(clusters.isEmpty, "Single photo should not create a cluster")
    }
    
    func testClusterTwoSimilarPhotos() async throws {
        // Given: Two photos with high similarity
        let featurePrint1 = try await makeFeaturePrint(color: .blue)
        let featurePrint2 = try await makeFeaturePrint(color: .blue)
        let distance = try VisionFeaturePrintService().computeDistance(
            between: featurePrint1,
            and: featurePrint2
        )
        let candidates: [PhotoClusteringService.Candidate] = [
            .init(featurePrint: featurePrint1, creationDate: nil, location: nil),
            .init(featurePrint: featurePrint2, creationDate: nil, location: nil)
        ]
        
        // When: Clustering with medium threshold
        let clusters = try service.clusterCandidates(candidates, threshold: distance + 0.01)
        
        // Then: Should create one cluster
        XCTAssertEqual(clusters.count, 1, "Similar photos should be in same cluster")
        XCTAssertEqual(clusters.first?.indices.count, 2, "Cluster should contain both photos")
    }
    
    func testClusterTwoDifferentPhotos() async throws {
        // Given: Two photos with low similarity
        let featurePrint1 = try await makeFeaturePrint(color: .red)
        let featurePrint2 = try await makeFeaturePrint(color: .green)
        let distance = try VisionFeaturePrintService().computeDistance(
            between: featurePrint1,
            and: featurePrint2
        )
        let candidates: [PhotoClusteringService.Candidate] = [
            .init(featurePrint: featurePrint1, creationDate: nil, location: nil),
            .init(featurePrint: featurePrint2, creationDate: nil, location: nil)
        ]
        
        // When: Clustering with strict threshold
        let clusters = try service.clusterCandidates(
            candidates,
            threshold: max(0.0, distance - 0.01)
        )
        
        // Then: Different photos should not form a cluster
        XCTAssertTrue(clusters.isEmpty, "Different photos should not be clustered")
    }
    
    func testCompleteLinkAvoidsChainMerging() async throws {
        // Given: A~B and B~C, but A not similar to C directly
        let featurePrint1 = try await makeFeaturePrint(color: .red)
        let featurePrint2 = try await makeFeaturePrint(color: .green)
        let featurePrint3 = try await makeFeaturePrint(color: .blue)
        
        let observations = [featurePrint1, featurePrint2, featurePrint3]
        let idMap = Dictionary(uniqueKeysWithValues: observations.enumerated().map {
            (ObjectIdentifier($0.element), $0.offset)
        })
        let distances: [[Float]] = [
            [0.0, 0.1, 0.9],
            [0.1, 0.0, 0.1],
            [0.9, 0.1, 0.0]
        ]
        
        let service = PhotoClusteringService(
            distanceProvider: { obs1, obs2 in
            guard let i = idMap[ObjectIdentifier(obs1)],
                  let j = idMap[ObjectIdentifier(obs2)] else {
                return 999.0
            }
            return distances[i][j]
        },
            enablePreFilter: false
        )
        
        let candidates: [PhotoClusteringService.Candidate] = [
            .init(featurePrint: featurePrint1, creationDate: nil, location: nil),
            .init(featurePrint: featurePrint2, creationDate: nil, location: nil),
            .init(featurePrint: featurePrint3, creationDate: nil, location: nil)
        ]
        
        // When: Clustering with threshold that connects A~B and B~C
        let clusters = try service.clusterCandidates(candidates, threshold: 0.2)
        
        // Then: Cluster should not merge via chain similarity
        XCTAssertEqual(clusters.count, 1, "Chain similarity should not merge all three")
        XCTAssertEqual(clusters.first?.indices.count, 2, "Cluster should contain only the directly similar pair")
    }
    
    func testHighThresholdCreatesFewerClusters() async throws {
        // Given: Three photos with varying similarities
        let similarPrint1 = try await makeFeaturePrint(color: .purple)
        let similarPrint2 = try await makeFeaturePrint(color: .purple)
        let differentPrint = try await makeFeaturePrint(color: .orange)
        let similarDistance = try VisionFeaturePrintService().computeDistance(
            between: similarPrint1,
            and: similarPrint2
        )
        let differentDistance = try VisionFeaturePrintService().computeDistance(
            between: similarPrint1,
            and: differentPrint
        )
        let candidates: [PhotoClusteringService.Candidate] = [
            .init(featurePrint: similarPrint1, creationDate: nil, location: nil),
            .init(featurePrint: similarPrint2, creationDate: nil, location: nil),
            .init(featurePrint: differentPrint, creationDate: nil, location: nil)
        ]
        
        // When: Clustering with low threshold (stricter)
        let strictClusters = try service.clusterCandidates(
            candidates,
            threshold: min(similarDistance + 0.01, max(0.0, differentDistance - 0.01))
        )
        
        // When: Clustering with high threshold (more lenient)
        let lenientClusters = try service.clusterCandidates(
            candidates,
            threshold: max(similarDistance + 0.01, differentDistance + 0.01)
        )
        
        // Then: Higher threshold should create fewer (or equal) clusters
        XCTAssertLessThanOrEqual(
            lenientClusters.count,
            strictClusters.count,
            "Higher threshold should create fewer separate clusters"
        )
    }
    
    func testClusterAverageSimilarity() async throws {
        // Given: Cluster of similar photos
        let featurePrint1 = try await makeFeaturePrint(color: .yellow)
        let featurePrint2 = try await makeFeaturePrint(color: .yellow)
        let featurePrint3 = try await makeFeaturePrint(color: .yellow)
        let distance = try VisionFeaturePrintService().computeDistance(
            between: featurePrint1,
            and: featurePrint2
        )
        let candidates: [PhotoClusteringService.Candidate] = [
            .init(featurePrint: featurePrint1, creationDate: nil, location: nil),
            .init(featurePrint: featurePrint2, creationDate: nil, location: nil),
            .init(featurePrint: featurePrint3, creationDate: nil, location: nil)
        ]
        
        // When: Clustering
        let clusters = try service.clusterCandidates(candidates, threshold: distance + 0.01)
        
        // Then: Average similarity should be calculated
        XCTAssertEqual(clusters.count, 1)
        let avgSimilarity = clusters.first?.averageSimilarity ?? 0.0
        XCTAssertGreaterThan(avgSimilarity, 0.95, "Average similarity should be high for similar photos")
        XCTAssertLessThanOrEqual(avgSimilarity, 1.0, "Average similarity should not exceed 1.0")
    }
    
    func testMinimumClusterSize() async throws {
        // Given: Photos that would create very small clusters
        let featurePrint = try await makeFeaturePrint(color: .cyan)
        let candidates: [PhotoClusteringService.Candidate] = [
            .init(featurePrint: featurePrint, creationDate: nil, location: nil)
        ]
        
        // When: Clustering
        let clusters = try service.clusterCandidates(candidates, threshold: 0.9)
        
        // Then: Clusters should have at least minClusterSize (2)
        XCTAssertTrue(clusters.isEmpty, "Single photo should not form a cluster")
    }
    
    // MARK: - Helper Methods
    
    private func makeFeaturePrint(color: UIColor) async throws -> VNFeaturePrintObservation {
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        guard let cgImage = image.cgImage else {
            throw NSError(domain: "PhotoClusteringServiceTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create CGImage"
            ])
        }

        do {
            let featurePrint = try await VisionFeaturePrintService().generateFeaturePrint(from: cgImage)
            return try XCTUnwrap(featurePrint)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSOSStatusErrorDomain {
                throw XCTSkip("Vision feature print unavailable: \(nsError.localizedDescription)")
            }
            throw error
        }
    }
}
