import Foundation
import Testing
import ImageIO
import Photos
@testable import Core

@MainActor
@Suite struct PHAssetExtensionsTests {
    
    // MARK: - Image Data Loading Tests
    
    @Test(.enabled(if: PhotoLibrary.hasImage(), "No photos available in library for testing"))
    func testLoadFullResolutionImageData() async throws {
        // Given: A PHAsset from photo library
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        let asset = try #require(fetchResult.firstObject)
        
        // When: Loading full resolution image data
        let imageData = try await asset.loadFullResolutionImageData()
        
        // Then: Should return data
        #expect(imageData != nil, "Image data should not be nil")
        #expect(imageData?.count ?? 0 > 0, "Image data should have content")
    }
    
    @Test(.enabled(if: PhotoLibrary.hasImage(), "No photos available in library for testing"))
    func testLoadImageDataMultipleTimes() async throws {
        // Given: A PHAsset
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        let asset = try #require(fetchResult.firstObject)
        
        // When: Loading image data multiple times
        let data1 = try await asset.loadFullResolutionImageData()
        let data2 = try await asset.loadFullResolutionImageData()
        
        // Then: Should return same data
        #expect(data1 != nil)
        #expect(data2 != nil)
        #expect(data1?.count == data2?.count, "Multiple loads should return same data size")
    }
    
    @Test(.enabled(if: PhotoLibrary.hasImage(), "No photos available in library for testing"))
    func testImageDataIsValidFormat() async throws {
        // Given: A PHAsset
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        let asset = try #require(fetchResult.firstObject)
        
        // When: Loading image data
        guard let imageData = try await asset.loadFullResolutionImageData() else {
            Issue.record("Failed to load image data")
            return
        }
        
        // Then: Should be valid image data on every supported platform.
        let source = CGImageSourceCreateWithData(imageData as CFData, nil)
        #expect(source != nil, "Image data should be a valid image format")
    }
    
    // MARK: - Performance Tests
    
    @Test(.enabled(if: PhotoLibrary.hasImage(), "No photos available for performance testing"))
    func testImageLoadingPerformance() async throws {
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 5
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        try #require(fetchResult.count > 0)
        
        // Measure time to load 5 images
        let startTime = Date()
        
        for i in 0..<min(5, fetchResult.count) {
            let asset = fetchResult.object(at: i)
            _ = try? await asset.loadFullResolutionImageData()
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: Should complete in reasonable time (< 10 seconds for 5 images)
        #expect(duration < 10.0, "Loading 5 images should take less than 10 seconds")
    }
    
    // MARK: - Error Handling Tests
    
    @Test(.enabled(if: PhotoLibrary.hasVideo(), "No video assets available for testing"))
    func testLoadImageDataHandlesInvalidAsset() async throws {
        // Given: Fetch options that might return no results
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        fetchOptions.fetchLimit = 1
        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        
        let videoAsset = try #require(fetchResult.firstObject)
        
        // When: Attempting to load image data from video asset
        // Then: Should either return nil or throw error gracefully
        _ = try? await videoAsset.loadFullResolutionImageData()
        
        // Video assets might return thumbnail data or nil
        // Just verify it doesn't crash
        #expect(true, "Should handle video asset gracefully")
    }

    // MARK: - PhotoKitRequestCoordinator Timeout/Cancellation Tests

    @Test func testRequestCoordinatorCancellationBeforeInstallResumesExactlyOnce() async {
        let coordinator = PhotoKitRequestCoordinator<Data?>(manager: .default())
        coordinator.cancel()

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                #expect(!(coordinator.install(continuation)))
                coordinator.timeout()
            } as Data?
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func testRequestCoordinatorTimeoutResolvesNilExactlyOnce() async throws {
        let coordinator = PhotoKitRequestCoordinator<Data?>(manager: .default())

        let data = try await withCheckedThrowingContinuation { continuation in
            #expect(coordinator.install(continuation))
            coordinator.timeout()
            coordinator.finish(with: .success(Data([1])))
        } as Data?

        #expect(data == nil)
    }
}

/// Whether the photo library holds an asset for the PhotoKit-backed tests above.
/// With an empty library (a host or simulator without photos) those tests are skipped.
private enum PhotoLibrary {
    static func hasImage() -> Bool {
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        return PHAsset.fetchAssets(with: .image, options: fetchOptions).firstObject != nil
    }

    static func hasVideo() -> Bool {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        fetchOptions.fetchLimit = 1
        return PHAsset.fetchAssets(with: fetchOptions).firstObject != nil
    }
}
