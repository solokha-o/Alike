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
        // Checked before the versions on purpose. Once Alike's own enhancement
        // is on the asset, these signals are the only surviving measurement of
        // the original; a model or thumbnail version bump cannot recover them,
        // it can only cause the enhanced pixels to be measured instead. The
        // weights are applied at ranking time, so a newer model still scores
        // this photo with today's formula.
        if isAlikeEnhanced { return true }
        guard self.scoringModelVersion == scoringModelVersion,
              self.thumbnailConfigVersion == thumbnailConfigVersion else {
            return false
        }
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
