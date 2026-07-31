import Core
import CoreGraphics
import Foundation
import os
@preconcurrency import Photos
#if canImport(UIKit)
import UIKit
#endif

struct BlurAnalysisAssetSnapshot: Equatable, Sendable {
    let localIdentifier: String
    let isScreenshot: Bool
    let isFavorite: Bool
    let estimatedCleanupBytes: Int64
}

struct BlurAnalysisCandidate: Equatable, Sendable {
    let localIdentifier: String
    let sharpnessScore: Double
    let estimatedCleanupBytes: Int64
}

private struct IndexedBlurAnalysisResult<Output: Sendable>: Sendable {
    let index: Int
    let value: Output?
}

enum BlurAnalysisTaskPool {
    static func compactMap<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        maxConcurrentTasks: Int,
        progress: @Sendable @escaping (Double) -> Void = { _ in },
        operation: @escaping @Sendable (Input) async throws -> Output?
    ) async throws -> [Output] {
        guard !inputs.isEmpty else { return [] }

        let taskLimit = min(max(maxConcurrentTasks, 1), inputs.count)
        return try await withThrowingTaskGroup(
            of: IndexedBlurAnalysisResult<Output>.self
        ) { group in
            var results: [IndexedBlurAnalysisResult<Output>] = []
            results.reserveCapacity(inputs.count)
            var nextIndex = 0
            var completedCount = 0

            func addTask(at index: Int) {
                let input = inputs[index]
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let value = try await operation(input)
                        try Task.checkCancellation()
                        return IndexedBlurAnalysisResult(index: index, value: value)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        AppLog.photoKit.debug(
                            "\(AppLog.tag(.error, "Skipping blur candidate after thumbnail failure: \(error.localizedDescription)"))"
                        )
                        return IndexedBlurAnalysisResult(index: index, value: nil)
                    }
                }
            }

            while nextIndex < taskLimit {
                addTask(at: nextIndex)
                nextIndex += 1
            }

            while let result = try await group.next() {
                results.append(result)
                completedCount += 1
                progress(Double(completedCount) / Double(inputs.count))
                if nextIndex < inputs.count {
                    addTask(at: nextIndex)
                    nextIndex += 1
                }
            }

            return results
                .sorted { $0.index < $1.index }
                .compactMap(\.value)
        }
    }
}

enum BlurCandidateSelector {
    static let maxWorstPercentile = 0.08
    static let absoluteSharpnessFloor = 10.0
    static let relativeToMedianMultiplier = 0.55
    static let minimumPopulation = 12

    static func selectCandidates(from candidates: [BlurAnalysisCandidate]) -> [BlurAnalysisCandidate] {
        guard candidates.count >= minimumPopulation else { return [] }

        let sorted = candidates.sorted {
            if $0.sharpnessScore != $1.sharpnessScore {
                return $0.sharpnessScore < $1.sharpnessScore
            }
            if $0.estimatedCleanupBytes != $1.estimatedCleanupBytes {
                return $0.estimatedCleanupBytes > $1.estimatedCleanupBytes
            }
            return $0.localIdentifier < $1.localIdentifier
        }

        let medianSharpness = medianScore(from: sorted)
        let adaptiveFloor = min(absoluteSharpnessFloor, medianSharpness * relativeToMedianMultiplier)
        let worstCount = max(1, Int(floor(Double(sorted.count) * maxWorstPercentile)))

        return Array(sorted.prefix(worstCount)).filter { $0.sharpnessScore <= adaptiveFloor }
    }

    private static func medianScore(from sorted: [BlurAnalysisCandidate]) -> Double {
        let middleIndex = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middleIndex - 1].sharpnessScore + sorted[middleIndex].sharpnessScore) / 2
        }
        return sorted[middleIndex].sharpnessScore
    }
}

struct BlurSharpnessScorer {
    func score(image: CGImage) -> Double {
        guard let pixels = grayscalePixels(from: image, dimension: 64) else {
            return .greatestFiniteMagnitude
        }
        guard pixels.width > 2, pixels.height > 2 else {
            return .greatestFiniteMagnitude
        }

        var total: Double = 0
        var sampleCount = 0

        for y in 1..<(pixels.height - 1) {
            for x in 1..<(pixels.width - 1) {
                let center = Double(pixels[x, y])
                let laplacian = abs(
                    4 * center
                    - Double(pixels[x - 1, y])
                    - Double(pixels[x + 1, y])
                    - Double(pixels[x, y - 1])
                    - Double(pixels[x, y + 1])
                )
                total += laplacian
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return .greatestFiniteMagnitude }
        return total / Double(sampleCount)
    }

    private func grayscalePixels(from image: CGImage, dimension: Int) -> GrayscalePixels? {
        let width = dimension
        let height = dimension
        let bytesPerRow = width
        var data = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return GrayscalePixels(width: width, height: height, bytes: data)
    }
}

struct BlurAnalysisService: Sendable {
    private static let thumbnailTargetSize = CGSize(width: 128, height: 128)
    private static let maxConcurrentTasks = 4

    private let scorer: BlurSharpnessScorer
    private let imageProvider: @Sendable (PHAsset, CGSize) async throws -> CGImage?

    init(
        scorer: BlurSharpnessScorer = BlurSharpnessScorer(),
        imageProvider: @escaping @Sendable (PHAsset, CGSize) async throws -> CGImage? = Self.defaultImageProvider
    ) {
        self.scorer = scorer
        self.imageProvider = imageProvider
    }

    func makeSnapshot(
        from assets: [PHAsset],
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> CleanupCategorySnapshot? {
        let workItems = assets.compactMap { asset -> BlurAnalysisWorkItem? in
            guard !asset.mediaSubtypes.contains(.photoScreenshot), !asset.isFavorite else {
                return nil
            }
            return BlurAnalysisWorkItem(
                asset: asset,
                localIdentifier: asset.localIdentifier,
                estimatedCleanupBytes: asset.estimatedCleanupBytes
            )
        }

        let imageProvider = self.imageProvider
        let scorer = self.scorer
        let candidates: [BlurAnalysisCandidate] = try await BlurAnalysisTaskPool.compactMap(
            workItems,
            maxConcurrentTasks: Self.maxConcurrentTasks,
            progress: progress
        ) { workItem in
            guard let image = try await imageProvider(workItem.asset, Self.thumbnailTargetSize) else {
                return nil
            }

            let sharpness = scorer.score(image: image)
            guard sharpness.isFinite else { return nil }

            return BlurAnalysisCandidate(
                localIdentifier: workItem.localIdentifier,
                sharpnessScore: sharpness,
                estimatedCleanupBytes: workItem.estimatedCleanupBytes
            )
        }

        let selected = BlurCandidateSelector.selectCandidates(from: candidates)
        guard !selected.isEmpty else { return nil }

        return CleanupCategorySnapshot(
            kind: .blurredPhotos,
            localIdentifiers: selected.map(\.localIdentifier),
            assetCount: selected.count,
            estimatedSavingsBytes: selected.reduce(into: Int64(0)) { $0 += $1.estimatedCleanupBytes }
        )
    }
}

private struct BlurAnalysisWorkItem: @unchecked Sendable {
    let asset: PHAsset
    let localIdentifier: String
    let estimatedCleanupBytes: Int64
}

private struct GrayscalePixels: Sendable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    subscript(_ x: Int, _ y: Int) -> UInt8 {
        bytes[(y * width) + x]
    }
}

private extension BlurAnalysisService {
    static func defaultImageProvider(asset: PHAsset, targetSize: CGSize) async throws -> CGImage? {
        #if canImport(UIKit)
        let requestState = BlurThumbnailRequestState()
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
final class BlurThumbnailRequestState: @unchecked Sendable {
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
