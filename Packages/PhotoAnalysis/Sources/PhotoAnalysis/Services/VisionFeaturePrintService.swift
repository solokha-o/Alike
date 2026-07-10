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
        8,
        max(2, ProcessInfo.processInfo.activeProcessorCount)
    )
    
    public init() {}
    
    /// Generate feature print for a single asset
    public func generateFeaturePrint(for asset: PHAsset) async throws -> VNFeaturePrintObservation? {
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
    func generateFeaturePrint(
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
    public func computeDistance(
        between observation1: VNFeaturePrintObservation,
        and observation2: VNFeaturePrintObservation
    ) throws -> Float {
        var distance: Float = 0.0
        try observation1.computeDistance(&distance, to: observation2)
        return distance
    }
    
    /// Batch process multiple assets
    public func generateFeaturePrints(
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

private struct ThumbnailCGImage {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
}

private extension VisionFeaturePrintService {
    func loadThumbnailCGImage(
        for asset: PHAsset,
        targetSize: CGSize
    ) async throws -> ThumbnailCGImage? {
        try await withCheckedThrowingContinuation { continuation in
            let didResume = OSAllocatedUnfairLock(initialState: false)
            let requestId = OSAllocatedUnfairLock(initialState: PHInvalidImageRequestID)

            func resumeOnce(_ action: () -> Void) {
                let shouldResume = didResume.withLock { state in
                    if state { return false }
                    state = true
                    return true
                }
                guard shouldResume else { return }
                action()
            }

            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            // Avoid iCloud download/auth errors that can stall scans.
            options.isNetworkAccessAllowed = false
            options.isSynchronous = true

            Task { @MainActor in
                let id = PHImageManager.default().requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { data, _, orientation, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        let nsError = error as NSError
                        if Self.shouldSkipImageDataRequest(for: nsError) {
                            resumeOnce { continuation.resume(returning: nil) }
                        } else {
                            AppLog.photoKit.error(
                                "\(AppLog.tag(.error, "Image data request error: \(error.localizedDescription)"))"
                            )
                            resumeOnce { continuation.resume(throwing: error) }
                        }
                        return
                    }

                    let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                    if cancelled {
                        resumeOnce { continuation.resume(returning: nil) }
                        return
                    }

                    let isInCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                    if isInCloud {
                        resumeOnce { continuation.resume(returning: nil) }
                        return
                    }

                    guard let data,
                          let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                        resumeOnce { continuation.resume(returning: nil) }
                        return
                    }

                    let thumbOptions: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: max(targetSize.width, targetSize.height),
                        kCGImageSourceCreateThumbnailWithTransform: true
                    ]

                    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
                        resumeOnce { continuation.resume(returning: nil) }
                        return
                    }

                    resumeOnce {
                        continuation.resume(
                            returning: ThumbnailCGImage(
                                cgImage: cgImage,
                                orientation: orientation
                            )
                        )
                    }
                }
                requestId.withLock { $0 = id }
            }

            Task.detached {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                let alreadyResumed = didResume.withLock { $0 }
                guard !alreadyResumed else { return }
                let id = requestId.withLock { $0 }
                if id != PHInvalidImageRequestID {
                    PHImageManager.default().cancelImageRequest(id)
                }
                resumeOnce { continuation.resume(returning: nil) }
            }
        }
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
