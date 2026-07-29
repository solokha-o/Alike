import Foundation
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
