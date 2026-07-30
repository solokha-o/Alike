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

                let requestID = manager.requestImage(
                    for: self,
                    targetSize: targetSize,
                    contentMode: PhotoImageRequestSizePolicy.contentMode(for: targetSize),
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

private final class PhotoKitRequestCoordinator<Value: Sendable>: @unchecked Sendable {
    private let manager: PHImageManager
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var requestID: PHImageRequestID?
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

    func cancel() {
        lock.lock()
        isCancelled = true
        let requestID = requestID
        let continuation = isFinished ? nil : continuation
        self.continuation = nil
        isFinished = true
        lock.unlock()

        if let requestID {
            manager.cancelImageRequest(requestID)
        }
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
        self.continuation = nil
        lock.unlock()

        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
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
    public static func isValid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    /// PhotoKit requires `.default` when the request asks for the maximum size; pairing that size
    /// with `.aspectFit` is undefined and can make the request fail instead of returning an image.
    public static func contentMode(for size: CGSize) -> PHImageContentMode {
        isMaximumSize(size) ? .default : .aspectFit
    }

    static func isMaximumSize(_ size: CGSize) -> Bool {
        size.width >= PHImageManagerMaximumSize.width
            || size.height >= PHImageManagerMaximumSize.height
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
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public var formattedModificationDate: String? {
        guard let date = modificationDate else { return nil }
        let formatter = DateFormatter()
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
