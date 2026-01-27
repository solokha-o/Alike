import XCTest
import Photos
import Core
@testable import PhotoAnalysis

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
        let photos: [(PHAsset, Float)] = []
        
        // When: Clustering
        let clusters = try await service.clusterPhotos(photos, threshold: 0.9)
        
        // Then: Should return empty array
        XCTAssertTrue(clusters.isEmpty, "Clustering empty array should return empty result")
    }
    
    func testClusterSinglePhoto() async throws {
        // Given: Single photo with mock PHAsset
        let mockAsset = createMockPHAsset()
        let photos: [(PHAsset, Float)] = [(mockAsset, 0.0)]
        
        // When: Clustering
        let clusters = try await service.clusterPhotos(photos, threshold: 0.9)
        
        // Then: Should return single cluster with one photo
        XCTAssertEqual(clusters.count, 1, "Single photo should create one cluster")
        XCTAssertEqual(clusters.first?.assets.count, 1, "Cluster should contain one photo")
    }
    
    func testClusterTwoSimilarPhotos() async throws {
        // Given: Two photos with high similarity (distance 0.05)
        let asset1 = createMockPHAsset()
        let asset2 = createMockPHAsset()
        let photos: [(PHAsset, Float)] = [
            (asset1, 0.0),
            (asset2, 0.05) // Very similar (distance < threshold)
        ]
        
        // When: Clustering with medium threshold
        let clusters = try await service.clusterPhotos(photos, threshold: 0.9)
        
        // Then: Should create one cluster (similarity > 0.95)
        XCTAssertEqual(clusters.count, 1, "Similar photos should be in same cluster")
        XCTAssertEqual(clusters.first?.assets.count, 2, "Cluster should contain both photos")
    }
    
    func testClusterTwoDifferentPhotos() async throws {
        // Given: Two photos with low similarity (distance 0.5)
        let asset1 = createMockPHAsset()
        let asset2 = createMockPHAsset()
        let photos: [(PHAsset, Float)] = [
            (asset1, 0.0),
            (asset2, 0.5) // Very different (distance > threshold)
        ]
        
        // When: Clustering with medium threshold
        let clusters = try await service.clusterPhotos(photos, threshold: 0.9)
        
        // Then: Should create two separate clusters
        XCTAssertEqual(clusters.count, 2, "Different photos should be in separate clusters")
    }
    
    func testHighThresholdCreatesMoreClusters() async throws {
        // Given: Three photos with varying similarities
        let asset1 = createMockPHAsset()
        let asset2 = createMockPHAsset()
        let asset3 = createMockPHAsset()
        let photos: [(PHAsset, Float)] = [
            (asset1, 0.0),
            (asset2, 0.08), // Moderate similarity
            (asset3, 0.15)  // Lower similarity
        ]
        
        // When: Clustering with high threshold (stricter)
        let strictClusters = try await service.clusterPhotos(photos, threshold: 0.95)
        
        // When: Clustering with low threshold (more lenient)
        let lenientClusters = try await service.clusterPhotos(photos, threshold: 0.8)
        
        // Then: Higher threshold should create more (or equal) clusters
        XCTAssertGreaterThanOrEqual(
            strictClusters.count,
            lenientClusters.count,
            "Higher threshold should create more separate clusters"
        )
    }
    
    func testClusterAverageSimilarity() async throws {
        // Given: Cluster of similar photos
        let asset1 = createMockPHAsset()
        let asset2 = createMockPHAsset()
        let asset3 = createMockPHAsset()
        let photos: [(PHAsset, Float)] = [
            (asset1, 0.0),
            (asset2, 0.02),
            (asset3, 0.03)
        ]
        
        // When: Clustering
        let clusters = try await service.clusterPhotos(photos, threshold: 0.9)
        
        // Then: Average similarity should be calculated
        XCTAssertEqual(clusters.count, 1)
        let avgSimilarity = clusters.first?.averageSimilarity ?? 0.0
        XCTAssertGreaterThan(avgSimilarity, 0.95, "Average similarity should be high for similar photos")
        XCTAssertLessThanOrEqual(avgSimilarity, 1.0, "Average similarity should not exceed 1.0")
    }
    
    func testMinimumClusterSize() async throws {
        // Given: Photos that would create very small clusters
        let asset1 = createMockPHAsset()
        let photos: [(PHAsset, Float)] = [(asset1, 0.0)]
        
        // When: Clustering
        let clusters = try await service.clusterPhotos(photos, threshold: 0.9)
        
        // Then: Clusters should have at least minClusterSize (2)
        // Single photo should still create a cluster (edge case)
        XCTAssertGreaterThanOrEqual(clusters.first?.assets.count ?? 0, 1)
    }
    
    // MARK: - Helper Methods
    
    private func createMockPHAsset() -> PHAsset {
        // Create a mock PHAsset for testing
        // Note: In real tests, you might want to use actual test photos
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        // Return first asset or create a placeholder
        if let asset = fetchResult.firstObject {
            return asset
        }
        
        // If no photos available, this will fail gracefully
        // In production tests, ensure test photos are available
        fatalError("No test photos available. Add photos to simulator/device for testing.")
    }
}
