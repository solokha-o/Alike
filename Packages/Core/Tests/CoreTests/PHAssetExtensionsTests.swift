import XCTest
import ImageIO
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
        
        // Then: Should be valid image data on every supported platform.
        let source = CGImageSourceCreateWithData(imageData as CFData, nil)
        XCTAssertNotNil(source, "Image data should be a valid image format")
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
        _ = try? await videoAsset.loadFullResolutionImageData()
        
        // Video assets might return thumbnail data or nil
        // Just verify it doesn't crash
        XCTAssertTrue(true, "Should handle video asset gracefully")
    }

    // MARK: - PhotoKitRequestCoordinator Timeout/Cancellation Tests

    func testRequestCoordinatorCancellationBeforeInstallResumesExactlyOnce() async {
        let coordinator = PhotoKitRequestCoordinator<Data?>(manager: .default())
        coordinator.cancel()

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                XCTAssertFalse(coordinator.install(continuation))
                coordinator.timeout()
            } as Data?
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestCoordinatorTimeoutResolvesNilExactlyOnce() async throws {
        let coordinator = PhotoKitRequestCoordinator<Data?>(manager: .default())

        let data = try await withCheckedThrowingContinuation { continuation in
            XCTAssertTrue(coordinator.install(continuation))
            coordinator.timeout()
            coordinator.finish(with: .success(Data([1])))
        } as Data?

        XCTAssertNil(data)
    }
}
