import Foundation
import Photos

#if canImport(UIKit)
import UIKit

extension PHAsset {
    /// Load the asset as a UIImage
    @MainActor
    public func loadImage(targetSize: CGSize = CGSize(width: 300, height: 300)) async throws -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImage(
                for: self,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
}
#endif

extension PHAsset {
    /// Get full resolution image data for Vision processing.
    @MainActor
    public func loadFullResolutionImageData() async throws -> Data? {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(
                for: self,
                options: options
            ) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
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
