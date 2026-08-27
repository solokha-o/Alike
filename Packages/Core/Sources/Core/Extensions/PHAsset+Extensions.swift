import Foundation
import Photos

#if canImport(UIKit)
import UIKit

extension PHAsset {
    /// Load the asset as a UIImage
    @MainActor
    public func loadImage(targetSize: CGSize = CGSize(width: 300, height: 300)) async throws -> UIImage? {
        guard PhotoImageRequestSizePolicy.isValid(targetSize) else {
            throw PhotoImageRequestError.invalidTargetSize
        }

        let cacheKey = PhotoImageCacheKey(
            assetIdentifier: localIdentifier,
            modificationDate: modificationDate,
            targetSize: targetSize
        )
        if let cachedImage = PhotoImageCache.shared.image(for: cacheKey) {
            return cachedImage
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let manager = PHImageManager.default()
        let request = PhotoKitRequestCoordinator<UIImage?>(manager: manager)

        let image = try await withTaskCancellationHandler {
            try Task.checkCancellation()

            return try await withCheckedThrowingContinuation { continuation in
                guard request.install(continuation) else { return }
                request.startTimeout()

                let requestID = manager.requestImage(
                    for: self,
                    targetSize: targetSize,
                    // Always bounded: `isValid` above rejects the maximum-size sentinel, which is
                    // the only size PhotoKit would want `.default` for.
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    if photoInfoFlag(PHImageCancelledKey, in: info) {
                        request.finish(with: .failure(CancellationError()))
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        request.finish(with: .failure(error))
                    } else if photoInfoFlag(PHImageResultIsDegradedKey, in: info) {
                        return
                    } else if let image {
                        request.finish(with: .success(image))
                    } else {
                        request.finish(with: .failure(PhotoImageRequestError.imageUnavailable))
                    }
                }

                request.register(requestID)
            }
        } onCancel: {
            request.cancel()
        }

        if let image {
            PhotoImageCache.shared.insert(image, for: cacheKey)
        }
        return image
    }
}
#endif

final class PhotoKitRequestCoordinator<Value: Sendable & ExpressibleByNilLiteral>: @unchecked Sendable {
    private let manager: PHImageManager
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var requestID: PHImageRequestID?
    private var timeoutTask: Task<Void, Never>?
    private var isCancelled = false
    private var isFinished = false

    init(manager: PHImageManager) {
        self.manager = manager
    }

    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if isCancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func register(_ requestID: PHImageRequestID) {
        lock.lock()
        self.requestID = requestID
        let shouldCancel = isCancelled
        lock.unlock()

        if shouldCancel {
            manager.cancelImageRequest(requestID)
        }
    }

    /// PhotoKit's completion handler can fail to fire (stalled iCloud fetch, a
    /// suspended app, etc.). Without a timeout that leaves the caller's
    /// `PhotoImageLoadState` stuck at `.loading` forever with no retry path.
    func startTimeout() {
        let timeoutTask = Task.detached { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.timeout()
        }
        lock.lock()
        let shouldCancel = isFinished
        if !shouldCancel {
            self.timeoutTask = timeoutTask
        }
        lock.unlock()
        if shouldCancel { timeoutTask.cancel() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let requestID = requestID
        let continuation = isFinished ? nil : continuation
        let timeoutTask = isFinished ? nil : timeoutTask
        self.continuation = nil
        self.timeoutTask = nil
        isFinished = true
        lock.unlock()

        if let requestID {
            manager.cancelImageRequest(requestID)
        }
        timeoutTask?.cancel()
        continuation?.resume(throwing: CancellationError())
    }

    func finish(with result: Result<Value, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = continuation
        let timeoutTask = timeoutTask
        self.continuation = nil
        self.timeoutTask = nil
        lock.unlock()

        timeoutTask?.cancel()
        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    func timeout() {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let requestID = requestID
        let continuation = continuation
        self.continuation = nil
        self.timeoutTask = nil
        lock.unlock()

        if let requestID {
            manager.cancelImageRequest(requestID)
        }
        continuation?.resume(returning: nil)
    }
}

private func photoInfoFlag(_ key: String, in info: [AnyHashable: Any]?) -> Bool {
    (info?[key] as? NSNumber)?.boolValue ?? false
}

public enum PhotoImageRequestError: Error, Equatable, LocalizedError, Sendable {
    case invalidTargetSize
    case imageUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidTargetSize:
            "The requested photo size must have positive, finite dimensions."
        case .imageUnavailable:
            "PhotoKit did not return an image."
        }
    }
}

public enum PhotoImageRequestSizePolicy {
    /// Rejects the maximum-size sentinel explicitly rather than letting it fall out of the
    /// `> 0` checks: callers here always request a bounded size, and reading the rejection as
    /// an accident of the sentinel being negative is what made the earlier `>=` bug look safe.
    public static func isValid(_ size: CGSize) -> Bool {
        guard !isMaximumSize(size) else { return false }
        return size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    /// `PHImageManagerMaximumSize` is a sentinel — `(-1, -1)`, not a large size — so it has to be
    /// matched exactly. Comparing with `>=` classifies every ordinary request as the maximum one.
    static func isMaximumSize(_ size: CGSize) -> Bool {
        size.width == PHImageManagerMaximumSize.width
            && size.height == PHImageManagerMaximumSize.height
    }
}

extension PHAsset {
    /// Get full resolution image data for Vision processing.
    @MainActor
    public func loadFullResolutionImageData() async throws -> Data? {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let manager = PHImageManager.default()
        let request = PhotoKitRequestCoordinator<Data?>(manager: manager)

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()

            return try await withCheckedThrowingContinuation { continuation in
                guard request.install(continuation) else { return }
                request.startTimeout()

                let requestID = manager.requestImageDataAndOrientation(
                    for: self,
                    options: options
                ) { data, _, _, info in
                    if photoInfoFlag(PHImageCancelledKey, in: info) {
                        request.finish(with: .failure(CancellationError()))
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        request.finish(with: .failure(error))
                    } else {
                        request.finish(with: .success(data))
                    }
                }

                request.register(requestID)
            }
        } onCancel: {
            request.cancel()
        }
    }

    /// Platform-neutral metadata for display and cleanup estimates.
    public var displayMetadata: AssetMetadata {
        AssetMetadata(
            creationDate: creationDate,
            modificationDate: modificationDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            isFavorite: isFavorite,
            mediaType: mediaType,
            mediaSubtypes: mediaSubtypes,
            location: location.map {
                AssetLocation(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude
                )
            }
        )
    }

    public var estimatedCleanupBytes: Int64 {
        displayMetadata.estimatedCleanupBytes
    }
}

public struct AssetLocation: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum PhotoTrait: Equatable, Sendable {
    case screenshot
    case panorama
    case livePhoto
    case hdr
    case depthEffect
}

/// Metadata extracted from PHAsset
public struct AssetMetadata: Sendable {
    public let creationDate: Date?
    public let modificationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let isFavorite: Bool
    public let mediaType: PHAssetMediaType
    public let photoTraits: [PhotoTrait]
    public let location: AssetLocation?

    public init(
        creationDate: Date?,
        modificationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        isFavorite: Bool,
        mediaType: PHAssetMediaType,
        mediaSubtypes: PHAssetMediaSubtype = [],
        location: AssetLocation? = nil
    ) {
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isFavorite = isFavorite
        self.mediaType = mediaType
        self.photoTraits = Self.photoTraits(from: mediaSubtypes)
        self.location = location
    }
    
    public var resolution: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    public var megapixelCount: Double {
        Double(pixelWidth) * Double(pixelHeight) / 1_000_000
    }

    public var estimatedCleanupBytes: Int64 {
        let pixelArea = Int64(pixelWidth) * Int64(pixelHeight)
        return max(1, pixelArea / 2)
    }

    public var formattedCreationDate: String {
        guard let date = creationDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.locale = .alikeFormatting
        formatter.calendar = .alikeFormattingCalendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public var formattedModificationDate: String? {
        guard let date = modificationDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .alikeFormatting
        formatter.calendar = .alikeFormattingCalendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func photoTraits(from mediaSubtypes: PHAssetMediaSubtype) -> [PhotoTrait] {
        var traits: [PhotoTrait] = []

        if mediaSubtypes.contains(.photoScreenshot) {
            traits.append(.screenshot)
        }
        if mediaSubtypes.contains(.photoPanorama) {
            traits.append(.panorama)
        }
        if mediaSubtypes.contains(.photoLive) {
            traits.append(.livePhoto)
        }
        if mediaSubtypes.contains(.photoHDR) {
            traits.append(.hdr)
        }
        if mediaSubtypes.contains(.photoDepthEffect) {
            traits.append(.depthEffect)
        }

        return traits
    }
}
