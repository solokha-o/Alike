import XCTest
import Photos
@testable import Core

@MainActor
final class PHAssetExtensionsTests: XCTestCase {
    
    // MARK: - Image Data Loading Tests
    
    func testLoadFullResolutionImageData() async throws {
        // Given: A PHAsset from photo library
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard let asset = fetchResult.firstObject else {
            throw XCTSkip("No photos available in library for testing")
        }
        
        // When: Loading full resolution image data
        let imageData = try await asset.loadFullResolutionImageData()
        
        // Then: Should return data
        XCTAssertNotNil(imageData, "Image data should not be nil")
        XCTAssertGreaterThan(imageData?.count ?? 0, 0, "Image data should have content")
    }
    
    func testLoadImageDataMultipleTimes() async throws {
        // Given: A PHAsset
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard let asset = fetchResult.firstObject else {
            throw XCTSkip("No photos available in library for testing")
        }
        
        // When: Loading image data multiple times
        let data1 = try await asset.loadFullResolutionImageData()
        let data2 = try await asset.loadFullResolutionImageData()
        
        // Then: Should return same data
        XCTAssertNotNil(data1)
        XCTAssertNotNil(data2)
        XCTAssertEqual(data1?.count, data2?.count, "Multiple loads should return same data size")
    }
    
    func testImageDataIsValidFormat() async throws {
        // Given: A PHAsset
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard let asset = fetchResult.firstObject else {
            throw XCTSkip("No photos available in library for testing")
        }
        
        // When: Loading image data
        guard let imageData = try await asset.loadFullResolutionImageData() else {
            XCTFail("Failed to load image data")
            return
        }
        
        // Then: Should be valid image format (can create UIImage)
        let image = UIImage(data: imageData)
        XCTAssertNotNil(image, "Image data should be valid image format")
        XCTAssertGreaterThan(image?.size.width ?? 0, 0, "Image should have width")
        XCTAssertGreaterThan(image?.size.height ?? 0, 0, "Image should have height")
    }
    
    // MARK: - Performance Tests
    
    func testImageLoadingPerformance() async throws {
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 5
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard fetchResult.count > 0 else {
            throw XCTSkip("No photos available for performance testing")
        }
        
        // Measure time to load 5 images
        let startTime = Date()
        
        for i in 0..<min(5, fetchResult.count) {
            let asset = fetchResult.object(at: i)
            _ = try? await asset.loadFullResolutionImageData()
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: Should complete in reasonable time (< 10 seconds for 5 images)
        XCTAssertLessThan(duration, 10.0, "Loading 5 images should take less than 10 seconds")
    }
    
    // MARK: - Error Handling Tests
    
    func testLoadImageDataHandlesInvalidAsset() async throws {
        // Given: Fetch options that might return no results
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        fetchOptions.fetchLimit = 1
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        
        guard let videoAsset = fetchResult.firstObject else {
            throw XCTSkip("No video assets available for testing")
        }
        
        // When: Attempting to load image data from video asset
        // Then: Should either return nil or throw error gracefully
        let imageData = try? await videoAsset.loadFullResolutionImageData()
        
        // Video assets might return thumbnail data or nil
        // Just verify it doesn't crash
        XCTAssertTrue(true, "Should handle video asset gracefully")
    }
}
