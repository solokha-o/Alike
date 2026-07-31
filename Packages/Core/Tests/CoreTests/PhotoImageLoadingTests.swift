import Foundation
import Photos
import Testing
@testable import Core

@Suite("Photo image loading")
struct PhotoImageLoadingTests {
    @Test("Request sizes must be positive and finite")
    func requestSizeValidation() {
        #expect(PhotoImageRequestSizePolicy.isValid(CGSize(width: 300, height: 300)))
        #expect(!PhotoImageRequestSizePolicy.isValid(CGSize(width: 300, height: 0)))
        #expect(!PhotoImageRequestSizePolicy.isValid(CGSize(width: -1, height: 300)))
        #expect(!PhotoImageRequestSizePolicy.isValid(CGSize(width: CGFloat.infinity, height: 300)))
        #expect(!PhotoImageRequestSizePolicy.isValid(CGSize(width: 300, height: CGFloat.nan)))
    }

    @Test("Cache keys distinguish asset versions and requested sizes")
    func cacheKeyIdentity() {
        let modificationDate = Date(timeIntervalSinceReferenceDate: 100)
        let key = PhotoImageCacheKey(
            assetIdentifier: "asset-1",
            modificationDate: modificationDate,
            targetSize: CGSize(width: 300, height: 300)
        )

        #expect(key == PhotoImageCacheKey(
            assetIdentifier: "asset-1",
            modificationDate: modificationDate,
            targetSize: CGSize(width: 300, height: 300)
        ))
        #expect(key != PhotoImageCacheKey(
            assetIdentifier: "asset-1",
            modificationDate: modificationDate,
            targetSize: CGSize(width: 1_000, height: 1_000)
        ))
        #expect(key != PhotoImageCacheKey(
            assetIdentifier: "asset-1",
            modificationDate: modificationDate.addingTimeInterval(1),
            targetSize: CGSize(width: 300, height: 300)
        ))
    }

    @Test("Maximum-size requests use the content mode PhotoKit requires")
    func contentModeForRequestedSize() {
        #expect(PhotoImageRequestSizePolicy.contentMode(for: CGSize(width: 300, height: 300)) == .aspectFit)
        #expect(PhotoImageRequestSizePolicy.contentMode(for: PHImageManagerMaximumSize) == .default)
    }

    @Test("Only the maximum-size sentinel itself counts as a maximum-size request")
    func maximumSizeIsMatchedExactly() {
        #expect(PhotoImageRequestSizePolicy.isMaximumSize(PHImageManagerMaximumSize))
        // The sentinel is negative, so a `>=` comparison would swallow every ordinary request.
        #expect(!PhotoImageRequestSizePolicy.isMaximumSize(CGSize(width: 300, height: 300)))
        #expect(!PhotoImageRequestSizePolicy.isMaximumSize(CGSize(width: 1_893, height: 4_096)))
    }

    @Test("Fullscreen requests scale the viewport by zoom instead of asking for full resolution")
    func fullscreenTargetSizeUsesViewport() {
        let size = PhotoFullscreenImageSizePolicy.targetSize(
            viewportSize: CGSize(width: 390, height: 844),
            displayScale: 3,
            maximumZoomScale: 4
        )

        // 390*3*4 = 4680 exceeds the cap, so both sides shrink proportionally.
        #expect(max(size.width, size.height) == PhotoFullscreenImageSizePolicy.maximumPixelDimension)
        #expect(size.width < size.height)
        #expect(PhotoImageRequestSizePolicy.isValid(size))
        #expect(!PhotoImageRequestSizePolicy.isMaximumSize(size))
    }

    @Test("Fullscreen requests stay valid before the viewport is laid out")
    func fullscreenTargetSizeHandlesUnlaidOutViewport() {
        let size = PhotoFullscreenImageSizePolicy.targetSize(
            viewportSize: .zero,
            displayScale: 0,
            maximumZoomScale: .nan
        )

        #expect(PhotoImageRequestSizePolicy.isValid(size))
        #expect(size.width == PhotoFullscreenImageSizePolicy.fallbackPointDimension)
        #expect(size.height == PhotoFullscreenImageSizePolicy.fallbackPointDimension)
    }

    @Test("Fullscreen sizes round to whole pixels so cache keys stay stable")
    func fullscreenTargetSizeRoundsToWholePixels() {
        let size = PhotoFullscreenImageSizePolicy.targetSize(
            viewportSize: CGSize(width: 320.4, height: 480.6),
            displayScale: 2,
            maximumZoomScale: 1
        )

        #expect(size.width == size.width.rounded())
        #expect(size.height == size.height.rounded())
    }

    @Test("Cache cost uses decoded byte size and clamps overflow")
    func cacheCost() {
        #expect(PhotoImageCacheCostPolicy.byteCost(bytesPerRow: 1_200, height: 300) == 360_000)
        #expect(PhotoImageCacheCostPolicy.byteCost(bytesPerRow: 0, height: 300) == 0)
        #expect(PhotoImageCacheCostPolicy.byteCost(bytesPerRow: Int.max, height: 2) == Int.max)
    }

    @Test("A stale completion cannot replace a newer load")
    func staleCompletionIsIgnored() {
        var state = PhotoImageLoadState()
        let staleGeneration = state.begin()
        let currentGeneration = state.begin()

        let acceptedStaleCompletion = state.resolve(.loaded, generation: staleGeneration)
        #expect(!acceptedStaleCompletion)
        #expect(state.phase == .loading)
        let acceptedCurrentCompletion = state.resolve(.failed, generation: currentGeneration)
        #expect(acceptedCurrentCompletion)
        #expect(state.phase == .failed)
    }

    @Test("Retry can move a failed load to success")
    func retryAfterFailure() {
        var state = PhotoImageLoadState()
        let firstGeneration = state.begin()
        let acceptedFailure = state.resolve(.failed, generation: firstGeneration)
        #expect(acceptedFailure)

        let retryGeneration = state.begin()
        #expect(state.phase == .loading)
        let acceptedRetry = state.resolve(.loaded, generation: retryGeneration)
        #expect(acceptedRetry)
        #expect(state.phase == .loaded)
    }

    @Test("Cancellation returns only the current load to idle")
    func cancellation() {
        var state = PhotoImageLoadState()
        let generation = state.begin()

        let acceptedCancellation = state.resolve(.cancelled, generation: generation)
        #expect(acceptedCancellation)
        #expect(state.phase == .idle)
        let acceptedLateFailure = state.resolve(.failed, generation: generation)
        #expect(!acceptedLateFailure)
    }
}
