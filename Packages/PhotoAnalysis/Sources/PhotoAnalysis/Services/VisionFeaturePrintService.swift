import Foundation
import ImageIO
import Core
import os
@preconcurrency import Photos
@preconcurrency import Vision
#if canImport(UIKit)
import UIKit
#endif

/// Service that processes photo feature prints using Vision framework
public struct VisionFeaturePrintService: Sendable {
    private static let thumbnailTargetSize = CGSize(width: 512, height: 512)
    private static let progressEpsilon = 0.01
    private static let progressReportInterval: Duration = .milliseconds(400)
    private static let maxConcurrentTasks = min(
        4,
        max(2, ProcessInfo.processInfo.activeProcessorCount)
    )
    
    public init() {}
    
    /// Generate feature print for a single asset
    nonisolated public func generateFeaturePrint(for asset: PHAsset) async throws -> VNFeaturePrintObservation? {
        try Task.checkCancellation()

        #if canImport(UIKit)
        guard let thumbnail = try await loadThumbnailCGImage(
            for: asset,
            targetSize: Self.thumbnailTargetSize
        ) else {
            return nil
        }

        return try await generateFeaturePrint(from: thumbnail.cgImage, orientation: thumbnail.orientation)
        #else
        return nil
        #endif
    }
    
    /// Generate feature print from CGImage
    nonisolated func generateFeaturePrint(
        from cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> VNFeaturePrintObservation? {
        try autoreleasepool {
            let requestHandler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: orientation,
                options: [:]
            )
            let request = VNGenerateImageFeaturePrintRequest()
            
            try requestHandler.perform([request])
            
            return request.results?.first
        }
    }
    
    /// Calculate distance between two feature prints (lower = more similar)
    nonisolated public func computeDistance(
        between observation1: VNFeaturePrintObservation,
        and observation2: VNFeaturePrintObservation
    ) throws -> Float {
        var distance: Float = 0.0
        try observation1.computeDistance(&distance, to: observation2)
        return distance
    }
    
    /// Batch process multiple assets
    nonisolated public func generateFeaturePrints(
        for assets: [PHAsset],
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [(asset: PHAsset, featurePrint: VNFeaturePrintObservation?)] {
        guard !assets.isEmpty else { return [] }

        let total = assets.count
        let taskLimit = min(Self.maxConcurrentTasks, total)
        AppLog.vision.debug("\(AppLog.tag(.vision, "FeaturePrint batch start. total=\(total) concurrency=\(taskLimit)"))")

        return try await withThrowingTaskGroup(of: FeaturePrintTaskResult.self) { group in
            var results: [FeaturePrintTaskResult] = []
            results.reserveCapacity(total)

            var nextIndex = 0
            var completed = 0
            var nilCount = 0
            var lastReportedProgress = 0.0
            let clock = ContinuousClock()
            var lastReportedTime = clock.now

            func addTask(index: Int) {
                let asset = UncheckedSendableBox(assets[index])
                group.addTask {
                    try Task.checkCancellation()
                    let featurePrint = try await self.generateFeaturePrint(for: asset.value)
                    return FeaturePrintTaskResult(
                        index: index,
                        asset: asset.value,
                        featurePrint: featurePrint
                    )
                }
            }

            while nextIndex < taskLimit {
                addTask(index: nextIndex)
                nextIndex += 1
            }

            while let taskResult = try await group.next() {
                results.append(taskResult)
                completed += 1
                if taskResult.featurePrint == nil {
                    nilCount += 1
                }

                let currentProgress = Double(completed) / Double(total)
                let now = clock.now
                let elapsed = lastReportedTime.duration(to: now)
                if currentProgress - lastReportedProgress >= Self.progressEpsilon
                    || elapsed >= Self.progressReportInterval
                    || currentProgress == 1.0 {
                    lastReportedProgress = currentProgress
                    lastReportedTime = now
                    progress(currentProgress)
                }

                if nextIndex < total {
                    addTask(index: nextIndex)
                    nextIndex += 1
                }
            }

            AppLog.vision.debug(
                "\(AppLog.tag(.vision, "FeaturePrint batch done. completed=\(completed) success=\(completed - nilCount) nil=\(nilCount)"))"
            )

            return results
                .sorted { $0.index < $1.index }
                .map { (asset: $0.asset, featurePrint: $0.featurePrint) }
        }
    }
}

// MARK: - Private Helpers

private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

private struct FeaturePrintTaskResult: @unchecked Sendable {
    let index: Int
    let asset: PHAsset
    let featurePrint: VNFeaturePrintObservation?
}

#if canImport(UIKit)

struct ThumbnailCGImage {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
}

private extension VisionFeaturePrintService {
    static let thumbnailRequestQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.alike.photo-analysis.thumbnail-requests"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 4
        return queue
    }()

    nonisolated func loadThumbnailCGImage(
        for asset: PHAsset,
        targetSize: CGSize
    ) async throws -> ThumbnailCGImage? {
        let requestState = FeaturePrintThumbnailRequestState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard requestState.install(continuation) else { return }
                requestState.startTimeout()
                Self.thumbnailRequestQueue.addOperation {
                    guard requestState.beginRequest() else { return }

                    let options = PHImageRequestOptions()
                    options.deliveryMode = .fastFormat
                    options.resizeMode = .fast
                    // Avoid iCloud download/auth errors that can stall scans.
                    options.isNetworkAccessAllowed = false
                    // PhotoKit runs this handler before requestImage returns. Keep this
                    // synchronous work on the bounded operation queue, never MainActor
                    // or a cooperative task-group thread.
                    options.isSynchronous = true

                    let requestID = PHImageManager.default().requestImage(
                        for: asset,
                        targetSize: targetSize,
                        contentMode: .aspectFit,
                        options: options
                    ) { image, info in
                        if let error = info?[PHImageErrorKey] as? Error {
                            let nsError = error as NSError
                            if Self.shouldSkipImageDataRequest(for: nsError) {
                                requestState.finish(.success(nil))
                            } else {
                                AppLog.photoKit.error(
                                    "\(AppLog.tag(.error, "Image request error: \(error.localizedDescription)"))"
                                )
                                requestState.finish(.failure(error))
                            }
                            return
                        }

                        if (info?[PHImageCancelledKey] as? Bool) == true
                            || (info?[PHImageResultIsInCloudKey] as? Bool) == true {
                            requestState.finish(.success(nil))
                            return
                        }

                        guard let cgImage = image?.cgImage else {
                            requestState.finish(.success(nil))
                            return
                        }

                        requestState.finish(
                            .success(
                                ThumbnailCGImage(
                                    cgImage: cgImage,
                                    orientation: CGImagePropertyOrientation(image?.imageOrientation ?? .up)
                                )
                            )
                        )
                    }
                    requestState.setRequestID(requestID)
                }
            }
        } onCancel: {
            requestState.cancel()
        }
    }

}

final class FeaturePrintThumbnailRequestState: @unchecked Sendable {
    private struct State {
        var requestID = PHInvalidImageRequestID
        var continuation: CheckedContinuation<ThumbnailCGImage?, Error>?
        var timeoutTask: Task<Void, Never>?
        var isCancelled = false
        var isFinished = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func install(_ continuation: CheckedContinuation<ThumbnailCGImage?, Error>) -> Bool {
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
        if shouldCancel { PHImageManager.default().cancelImageRequest(requestID) }
    }

    /// Returns false when cancellation or timeout completed the continuation
    /// while this request was still waiting in the bounded operation queue.
    func beginRequest() -> Bool {
        state.withLock { state in
            !state.isCancelled && !state.isFinished
        }
    }

    func finish(_ result: Result<ThumbnailCGImage?, Error>) {
        let completion = state.withLock { state -> (CheckedContinuation<ThumbnailCGImage?, Error>?, Task<Void, Never>?)? in
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
        finishAndCancel(error: CancellationError())
    }

    func timeout() {
        if finishAndCancel(result: .success(nil)) {
            AppLog.photoKit.error(
                "\(AppLog.tag(.error, "Thumbnail request timed out after 15 seconds"))"
            )
        }
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

    private func finishAndCancel(error: Error) {
        _ = finishAndCancel(result: .failure(error))
    }

    @discardableResult
    private func finishAndCancel(result: Result<ThumbnailCGImage?, Error>) -> Bool {
        let cancellation = state.withLock { state -> (Bool, PHImageRequestID, CheckedContinuation<ThumbnailCGImage?, Error>?, Task<Void, Never>?) in
            guard !state.isFinished else { return (false, state.requestID, nil, nil) }
            state.isFinished = true
            if case .failure(let error) = result, error is CancellationError {
                state.isCancelled = true
            }
            defer {
                state.continuation = nil
                state.timeoutTask = nil
            }
            return (true, state.requestID, state.continuation, state.timeoutTask)
        }
        guard cancellation.0 else { return false }
        if cancellation.1 != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(cancellation.1)
        }
        cancellation.3?.cancel()
        cancellation.2?.resume(with: result)
        return true
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

#endif

extension VisionFeaturePrintService {
    static func shouldSkipImageDataRequest(for error: NSError) -> Bool {
        if error.domain == PHPhotosErrorDomain || error.domain == "com.apple.accounts" {
            return true
        }

        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return shouldSkipImageDataRequest(for: underlyingError)
        }

        return false
    }
}
