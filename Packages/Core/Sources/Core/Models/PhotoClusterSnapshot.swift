import Foundation
import Photos

public enum ClusterResurfacingState: String, Sendable, Codable {
    case unchanged
    case new
    case changed
}

public struct PhotoClusterAssetSnapshot: Equatable, Hashable, Sendable, Codable {
    public let localIdentifier: String
    public let creationDate: Date?
    public let modificationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let isFavorite: Bool

    public init(
        localIdentifier: String,
        creationDate: Date?,
        modificationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        isFavorite: Bool
    ) {
        self.localIdentifier = localIdentifier
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isFavorite = isFavorite
    }

    public init(asset: PHAsset) {
        self.init(
            localIdentifier: asset.localIdentifier,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            isFavorite: asset.isFavorite
        )
    }

    public var pixelArea: Int64 {
        Int64(pixelWidth) * Int64(pixelHeight)
    }
}

public struct PhotoClusterSnapshot: Identifiable, Equatable, Hashable, Sendable, Codable {
    public let id: UUID
    public let createdAt: Date
    public let averageSimilarity: Float
    public let assets: [PhotoClusterAssetSnapshot]

    public init(
        id: UUID,
        createdAt: Date,
        averageSimilarity: Float,
        assets: [PhotoClusterAssetSnapshot]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.averageSimilarity = averageSimilarity
        self.assets = assets
    }

    public init(cluster: PhotoCluster) {
        self.init(
            id: cluster.id,
            createdAt: cluster.createdAt,
            averageSimilarity: cluster.averageSimilarity,
            assets: cluster.assets.map(PhotoClusterAssetSnapshot.init)
        )
    }

    public var assetIdentifiers: Set<String> {
        Set(assets.map(\.localIdentifier))
    }

    public var bestShotLocalIdentifier: String? {
        PhotoClusterBestShot.bestShotLocalIdentifier(from: assets)
    }
}

public enum PhotoClusterBestShot {
    public static func bestShotLocalIdentifier(from snapshots: [PhotoClusterAssetSnapshot]) -> String? {
        snapshots.max(by: isPreferredAsset)?.localIdentifier
    }

    public static func isPreferredAsset(
        _ lhs: PhotoClusterAssetSnapshot,
        _ rhs: PhotoClusterAssetSnapshot
    ) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return !lhs.isFavorite && rhs.isFavorite
        }

        if lhs.pixelArea != rhs.pixelArea {
            return lhs.pixelArea < rhs.pixelArea
        }

        let lhsTimestamp = max(
            lhs.creationDate?.timeIntervalSince1970 ?? 0,
            lhs.modificationDate?.timeIntervalSince1970 ?? 0
        )
        let rhsTimestamp = max(
            rhs.creationDate?.timeIntervalSince1970 ?? 0,
            rhs.modificationDate?.timeIntervalSince1970 ?? 0
        )
        if lhsTimestamp != rhsTimestamp {
            return lhsTimestamp < rhsTimestamp
        }

        return lhs.localIdentifier > rhs.localIdentifier
    }
}
