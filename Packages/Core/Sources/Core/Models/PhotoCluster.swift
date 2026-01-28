import Foundation
import Photos

/// Represents a cluster of visually similar photos
public struct PhotoCluster: Identifiable, Hashable, Equatable, @unchecked Sendable {
    public let id: UUID
    public let assets: [PHAsset]
    public let createdAt: Date
    public let averageSimilarity: Float
    
    public init(
        id: UUID = UUID(),
        assets: [PHAsset],
        createdAt: Date = Date(),
        averageSimilarity: Float = 0.0
    ) {
        self.id = id
        self.assets = assets
        self.createdAt = createdAt
        self.averageSimilarity = averageSimilarity
    }
    
    /// Returns the count of photos in this cluster
    public var count: Int {
        assets.count
    }
    
    /// Returns the first asset to use as a thumbnail
    public var thumbnail: PHAsset? {
        assets.first
    }
}

// MARK: - Manual Equatable & Hashable
// PHAsset is not Equatable/Hashable, so synthesize these conformances manually
public extension PhotoCluster {
    static func == (lhs: PhotoCluster, rhs: PhotoCluster) -> Bool {
        lhs.id == rhs.id
    }
}

public extension PhotoCluster {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Preview Helpers
#if DEBUG
extension PhotoCluster {
    public static var mock: PhotoCluster {
        PhotoCluster(
            assets: [],
            averageSimilarity: 0.85
        )
    }
    
    public static var mockMultiple: [PhotoCluster] {
        (0..<5).map { _ in
            PhotoCluster(
                assets: [],
                averageSimilarity: Float.random(in: 0.7...0.95)
            )
        }
    }
}
#endif
