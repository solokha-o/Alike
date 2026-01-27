import XCTest
@preconcurrency import Vision
@preconcurrency import Photos
import Core
#if canImport(UIKit)
import UIKit
#endif
@testable import PhotoAnalysis

extension PHAsset: @unchecked Sendable {}
extension VNFeaturePrintObservation: @unchecked @retroactive Sendable {}

@MainActor
final class PhotoClusteringServiceTests: XCTestCase {
    var service: PhotoClusteringService!
    
    override func setUp() async throws {
        service = PhotoClusteringService()
    }
    
    override func tearDown() async throws {
        service = nil
    }
    
    // MARK: - Clustering Algorithm Tests
    
    func testClusterEmptyArray() async throws {
        // Given: Empty array
        let photos: [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)] = []
        
        // When: Clustering
        let clusters = try await service.clusterPhotos(photos, threshold: 0.9)
        
        // Then: Should return empty array
        XCTAssertTrue(clusters.isEmpty, "Clustering empty array should return empty result")
    }
    
    func testClusterSinglePhoto() async throws {
        // Given: Single photo with mock PHAsset
        let mockAsset = try createMockPHAsset()
        let featurePrint = try await makeFeaturePrint(color: .red)
        let photos: [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)] = [
            (asset: mockAsset, featurePrint: featurePrint)
        ]
        
        // When: Clustering
        let clusters = try await service.clusterPhotos(photos, threshold: 0.9)
        
        // Then: Single photo should not form a cluster (clusters require > 1 photo)
        XCTAssertTrue(clusters.isEmpty, "Single photo should not create a cluster")
    }
    
    func testClusterTwoSimilarPhotos() async throws {
        // Given: Two photos with high similarity
        let asset1 = try createMockPHAsset()
        let asset2 = try createMockPHAsset()
        let featurePrint1 = try await makeFeaturePrint(color: .blue)
        let featurePrint2 = try await makeFeaturePrint(color: .blue)
        let distance = try VisionFeaturePrintService().computeDistance(
            between: featurePrint1,
            and: featurePrint2
        )
        let photos: [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)] = [
            (asset: asset1, featurePrint: featurePrint1),
            (asset: asset2, featurePrint: featurePrint2)
        ]
        
        // When: Clustering with medium threshold
        let clusters = try await service.clusterPhotos(photos, threshold: distance + 0.01)
        
        // Then: Should create one cluster
        XCTAssertEqual(clusters.count, 1, "Similar photos should be in same cluster")
        XCTAssertEqual(clusters.first?.assets.count, 2, "Cluster should contain both photos")
    }
    
    func testClusterTwoDifferentPhotos() async throws {
        // Given: Two photos with low similarity
        let asset1 = try createMockPHAsset()
        let asset2 = try createMockPHAsset()
        let featurePrint1 = try await makeFeaturePrint(color: .red)
        let featurePrint2 = try await makeFeaturePrint(color: .green)
        let distance = try VisionFeaturePrintService().computeDistance(
            between: featurePrint1,
            and: featurePrint2
        )
        let photos: [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)] = [
            (asset: asset1, featurePrint: featurePrint1),
            (asset: asset2, featurePrint: featurePrint2)
        ]
        
        // When: Clustering with strict threshold
        let clusters = try await service.clusterPhotos(
            photos,
            threshold: max(0.0, distance - 0.01)
        )
        
        // Then: Different photos should not form a cluster
        XCTAssertTrue(clusters.isEmpty, "Different photos should not be clustered")
    }
    
    func testHighThresholdCreatesMoreClusters() async throws {
        // Given: Three photos with varying similarities
        let asset1 = try createMockPHAsset()
        let asset2 = try createMockPHAsset()
        let asset3 = try createMockPHAsset()
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
        let photos: [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)] = [
            (asset: asset1, featurePrint: similarPrint1),
            (asset: asset2, featurePrint: similarPrint2),
            (asset: asset3, featurePrint: differentPrint)
        ]
        
        // When: Clustering with low threshold (stricter)
        let strictClusters = try await service.clusterPhotos(
            photos,
            threshold: min(similarDistance + 0.01, max(0.0, differentDistance - 0.01))
        )
        
        // When: Clustering with high threshold (more lenient)
        let lenientClusters = try await service.clusterPhotos(
            photos,
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
        let asset1 = try createMockPHAsset()
        let asset2 = try createMockPHAsset()
        let asset3 = try createMockPHAsset()
        let featurePrint1 = try await makeFeaturePrint(color: .yellow)
        let featurePrint2 = try await makeFeaturePrint(color: .yellow)
        let featurePrint3 = try await makeFeaturePrint(color: .yellow)
        let distance = try VisionFeaturePrintService().computeDistance(
            between: featurePrint1,
            and: featurePrint2
        )
        let photos: [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)] = [
            (asset: asset1, featurePrint: featurePrint1),
            (asset: asset2, featurePrint: featurePrint2),
            (asset: asset3, featurePrint: featurePrint3)
        ]
        
        // When: Clustering
        let clusters = try await service.clusterPhotos(photos, threshold: distance + 0.01)
        
        // Then: Average similarity should be calculated
        XCTAssertEqual(clusters.count, 1)
        let avgSimilarity = clusters.first?.averageSimilarity ?? 0.0
        XCTAssertGreaterThan(avgSimilarity, 0.95, "Average similarity should be high for similar photos")
        XCTAssertLessThanOrEqual(avgSimilarity, 1.0, "Average similarity should not exceed 1.0")
    }
    
    func testMinimumClusterSize() async throws {
        // Given: Photos that would create very small clusters
        let asset1 = try createMockPHAsset()
        let featurePrint = try await makeFeaturePrint(color: .cyan)
        let photos: [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)] = [
            (asset: asset1, featurePrint: featurePrint)
        ]
        
        // When: Clustering
        let clusters = try await service.clusterPhotos(photos, threshold: 0.9)
        
        // Then: Clusters should have at least minClusterSize (2)
        XCTAssertTrue(clusters.isEmpty, "Single photo should not form a cluster")
    }
    
    // MARK: - Helper Methods
    
    private func createMockPHAsset() throws -> PHAsset {
        // Create a mock PHAsset for testing
        // Note: In real tests, you might want to use actual test photos
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        // Return first asset or create a placeholder
        if let asset = fetchResult.firstObject {
            return asset
        }

        throw XCTSkip("No test photos available. Add photos to simulator/device for testing.")
    }

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

        let featurePrint = try await VisionFeaturePrintService().generateFeaturePrint(from: cgImage)
        return try XCTUnwrap(featurePrint)
    }
}
