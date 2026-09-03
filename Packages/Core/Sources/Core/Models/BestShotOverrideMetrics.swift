import Foundation

/// Local, anonymous tally of how often the user replaces the recommended Best
/// Shot.
///
/// It is the calibration signal for the scoring weights, and it is deliberately
/// nothing more than counters: no identifiers, no photos, no dates, and nothing
/// that ever leaves the device.
public struct BestShotOverrideMetrics: Codable, Equatable, Sendable {
    /// Clusters where a Best Shot was actually recommended.
    public var recommendationCount: Int
    /// Recommendations the user replaced with a photo of their own choosing.
    public var manualOverrideCount: Int
    /// Recommendations shown as "probably best" that the user replaced. Tracked
    /// apart because a hedged pick being replaced is expected, not a miss.
    public var lowConfidenceOverrideCount: Int
    /// Clusters where the ranking offered nothing and the user chose alone.
    public var unresolvedManualPickCount: Int

    public init(
        recommendationCount: Int = 0,
        manualOverrideCount: Int = 0,
        lowConfidenceOverrideCount: Int = 0,
        unresolvedManualPickCount: Int = 0
    ) {
        self.recommendationCount = max(0, recommendationCount)
        self.manualOverrideCount = max(0, manualOverrideCount)
        self.lowConfidenceOverrideCount = max(0, lowConfidenceOverrideCount)
        self.unresolvedManualPickCount = max(0, unresolvedManualPickCount)
    }

    /// Share of recommendations the user replaced; the number the target
    /// "< 15 % manual replacements" is measured against.
    public var overrideRate: Double {
        guard recommendationCount > 0 else { return 0 }
        return min(1, Double(manualOverrideCount) / Double(recommendationCount))
    }

    public static let empty = BestShotOverrideMetrics()
}
