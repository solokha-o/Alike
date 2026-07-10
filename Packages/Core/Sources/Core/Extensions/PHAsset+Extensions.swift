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
            mediaType: mediaType
        )
    }

    public var estimatedCleanupBytes: Int64 {
        displayMetadata.estimatedCleanupBytes
    }
}

/// Metadata extracted from PHAsset
public struct AssetMetadata: Sendable {
    public let creationDate: Date?
    public let modificationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let isFavorite: Bool
    public let mediaType: PHAssetMediaType
    
    public var resolution: String {
        "\(pixelWidth) × \(pixelHeight)"
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
}
