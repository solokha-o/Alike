import Core
import CoreGraphics
import Foundation
import os
@preconcurrency import Photos
#if canImport(UIKit)
import UIKit
#endif

enum AnalysisImageProvider {
    /// One PhotoKit thumbnail request path, shared by blur detection and quality
    /// scoring, so both get the same timeout and cancellation behaviour.
    static func requestImage(asset: PHAsset, targetSize: CGSize) async throws -> CGImage? {
        #if canImport(UIKit)
        let requestState = AnalysisThumbnailRequestState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard requestState.install(continuation) else { return }

                let options = PHImageRequestOptions()
                options.deliveryMode = .fastFormat
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = false
                options.isSynchronous = false

                requestState.startTimeout()
                let requestID = PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        requestState.finish(.failure(error))
                        return
                    }

                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        requestState.finish(.failure(CancellationError()))
                        return
                    }

                    requestState.finish(.success(image?.cgImage))
                }
                requestState.setRequestID(requestID)
            }
        } onCancel: {
            requestState.cancel()
        }
        #else
        return nil
        #endif
    }
}

#if canImport(UIKit)
final class AnalysisThumbnailRequestState: @unchecked Sendable {
    private struct State {
        var requestID = PHInvalidImageRequestID
        var continuation: CheckedContinuation<CGImage?, Error>?
        var timeoutTask: Task<Void, Never>?
        var isCancelled = false
        var isFinished = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func install(_ continuation: CheckedContinuation<CGImage?, Error>) -> Bool {
        let shouldStart = state.withLock { state in
            guard !state.isCancelled, !state.isFinished else {
                return false
            }
            state.continuation = continuation
            return true
        }

        if !shouldStart {
            continuation.resume(throwing: CancellationError())
        }
        return shouldStart
    }

    func setRequestID(_ requestID: PHImageRequestID) {
        let shouldCancel = state.withLock { state in
            state.requestID = requestID
            return state.isCancelled || state.isFinished
        }
        if shouldCancel {
            PHImageManager.default().cancelImageRequest(requestID)
        }
    }

    func finish(_ result: Result<CGImage?, Error>) {
        let completion = state.withLock { state -> (CheckedContinuation<CGImage?, Error>?, Task<Void, Never>?)? in
            guard !state.isFinished else { return nil }
            state.isFinished = true
            defer {
                state.continuation = nil
                state.timeoutTask = nil
            }
            return (state.continuation, state.timeoutTask)
        }
        completion?.1?.cancel()
        completion?.0?.resume(with: result)
    }

    func cancel() {
        let cancellation = state.withLock { state -> (
            PHImageRequestID,
            CheckedContinuation<CGImage?, Error>?,
            Task<Void, Never>?
        ) in
            state.isCancelled = true
            guard !state.isFinished else {
                return (state.requestID, nil, nil)
            }
            state.isFinished = true
            defer {
                state.continuation = nil
                state.timeoutTask = nil
            }
            return (state.requestID, state.continuation, state.timeoutTask)
        }

        if cancellation.0 != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(cancellation.0)
        }
        cancellation.2?.cancel()
        cancellation.1?.resume(throwing: CancellationError())
    }

    func timeout() {
        let timeout = state.withLock { state -> (
            PHImageRequestID,
            CheckedContinuation<CGImage?, Error>?,
            Task<Void, Never>?
        ) in
            guard !state.isFinished else {
                return (state.requestID, nil, nil)
            }
            state.isFinished = true
            defer {
                state.continuation = nil
                state.timeoutTask = nil
            }
            return (state.requestID, state.continuation, state.timeoutTask)
        }

        if timeout.0 != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(timeout.0)
        }
        timeout.2?.cancel()
        timeout.1?.resume(returning: nil)
    }

    func startTimeout() {
        let timeoutTask = Task.detached { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.timeout()
        }
        let shouldCancel = state.withLock { state in
            guard !state.isFinished else { return true }
            state.timeoutTask = timeoutTask
            return false
        }
        if shouldCancel { timeoutTask.cancel() }
    }
}
#endif
