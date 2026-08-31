import Foundation

/// One cached quality measurement for one asset.
///
/// The cache key is `localIdentifier` + `sourceModificationDate` +
/// `scoringModelVersion` + `thumbnailConfigVersion`: any difference is a miss,
/// and that is the whole invalidation rule.
public struct PhotoQualityScore: Codable, Sendable, Equatable, Identifiable {
    public let localIdentifier: String
    public let sourceModificationDate: Date?
    public let scoringModelVersion: Int
    public let thumbnailConfigVersion: Int
    public let signals: PhotoQualitySignals
    public let scoredAt: Date
    /// Set once Alike's own auto-enhancement was applied (phase 2). Such an
    /// asset keeps its pre-enhancement signals and is not re-scored, so our own
    /// edit can never lift the score or hide the defects of the original.
    public let isAlikeEnhanced: Bool

    public var id: String { localIdentifier }

    public init(
        localIdentifier: String,
        sourceModificationDate: Date?,
        scoringModelVersion: Int,
        thumbnailConfigVersion: Int,
        signals: PhotoQualitySignals,
        scoredAt: Date = Date(),
        isAlikeEnhanced: Bool = false
    ) {
        self.localIdentifier = localIdentifier
        self.sourceModificationDate = sourceModificationDate
        self.scoringModelVersion = scoringModelVersion
        self.thumbnailConfigVersion = thumbnailConfigVersion
        self.signals = signals
        self.scoredAt = scoredAt
        self.isAlikeEnhanced = isAlikeEnhanced
    }

    /// Whether this cached row still answers for `modificationDate` under the
    /// supplied configuration versions.
    public func isFresh(
        modificationDate: Date?,
        scoringModelVersion: Int,
        thumbnailConfigVersion: Int
    ) -> Bool {
        guard self.scoringModelVersion == scoringModelVersion,
              self.thumbnailConfigVersion == thumbnailConfigVersion else {
            return false
        }
        // Our own enhancement rewrites `modificationDate`; re-scoring then would
        // measure the enhanced pixels, which is exactly what must not happen.
        if isAlikeEnhanced { return true }
        return Self.isSameDate(sourceModificationDate, modificationDate)
    }

    private static func isSameDate(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            // Core Data rounds dates to sub-millisecond precision on the way back.
            return abs(lhs.timeIntervalSinceReferenceDate - rhs.timeIntervalSinceReferenceDate) < 0.001
        default:
            return false
        }
    }
}
