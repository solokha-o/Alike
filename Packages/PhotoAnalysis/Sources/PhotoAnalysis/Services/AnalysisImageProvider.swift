import Core
import CoreGraphics
import Foundation
import os
@preconcurrency import Photos
#if canImport(UIKit)
import UIKit
#endif

enum AnalysisImageProvider {
    /// What the caller needs from the image, which is not the same thing for
    /// both analyses.
    enum Fidelity {
        /// Blur detection's first pass: whatever PhotoKit already has cached is
        /// good enough, and it must never wait on the network.
        case fastPass
        /// Best Shot scoring: the score is a comparison between photos, so it
        /// needs the real pixels at the requested size. A cached 60 px preview
        /// would make sharpness a measurement of PhotoKit's cache, not of the
        /// photo.
        case precise

        var requestOptions: PHImageRequestOptions {
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            switch self {
            case .fastPass:
                options.deliveryMode = .fastFormat
                options.resizeMode = .fast
                options.isNetworkAccessAllowed = false
            case .precise:
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .exact
                options.isNetworkAccessAllowed = true
            }
            return options
        }
    }

    /// Blur detection's image request.
    static func requestFastImage(asset: PHAsset, targetSize: CGSize) async throws -> CGImage? {
        try await requestImage(asset: asset, targetSize: targetSize, fidelity: .fastPass)
    }

    /// Best Shot scoring's image request.
    static func requestPreciseImage(asset: PHAsset, targetSize: CGSize) async throws -> CGImage? {
        try await requestImage(asset: asset, targetSize: targetSize, fidelity: .precise)
    }

    /// One PhotoKit thumbnail request path, shared by blur detection and quality
    /// scoring, so both get the same timeout and cancellation behaviour.
    static func requestImage(
        asset: PHAsset,
        targetSize: CGSize,
        fidelity: Fidelity
    ) async throws -> CGImage? {
        #if canImport(UIKit)
        let requestState = AnalysisThumbnailRequestState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard requestState.install(continuation) else { return }

                let options = fidelity.requestOptions

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
