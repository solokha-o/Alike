import Foundation
import Photos
import SwiftUI
import DesignSystem
import Storage

struct ReviewAssetSnapshot: Equatable, Sendable {
    let localIdentifier: String
    let isFavorite: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let modificationDate: Date?
    /// Measured once, off the main actor where possible. See `AssetByteSize`.
    let estimatedCleanupBytes: Int64

    init(asset: PHAsset) {
        self.localIdentifier = asset.localIdentifier
        self.isFavorite = asset.isFavorite
        self.pixelWidth = asset.pixelWidth
        self.pixelHeight = asset.pixelHeight
        self.creationDate = asset.creationDate
        self.modificationDate = asset.modificationDate
        self.estimatedCleanupBytes = asset.estimatedCleanupBytes
    }

    init(
        localIdentifier: String,
        isFavorite: Bool,
        pixelWidth: Int,
        pixelHeight: Int,
        creationDate: Date?,
        modificationDate: Date? = nil,
        estimatedCleanupBytes: Int64? = nil
    ) {
        self.localIdentifier = localIdentifier
        self.isFavorite = isFavorite
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.estimatedCleanupBytes = estimatedCleanupBytes
            ?? AssetByteSize.heuristicBytes(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    var photoClusterAssetSnapshot: PhotoClusterAssetSnapshot {
        PhotoClusterAssetSnapshot(
            localIdentifier: localIdentifier,
            creationDate: creationDate,
            modificationDate: modificationDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            isFavorite: isFavorite
        )
    }
}
