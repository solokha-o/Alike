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
