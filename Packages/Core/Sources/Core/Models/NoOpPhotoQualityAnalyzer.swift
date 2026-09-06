import Foundation
import Photos

/// Analyzer that measures nothing.
///
/// It is the default wherever no real analyzer is injected, so those hosts keep
/// the metadata-only Best Shot behaviour instead of losing the badge.
public struct NoOpPhotoQualityAnalyzer: PhotoQualityAnalyzing {
    public init() {}

    public func scores(for _: [PHAsset]) async throws -> [PhotoQualityScore] { [] }
}
