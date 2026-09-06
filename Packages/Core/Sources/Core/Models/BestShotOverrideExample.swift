import Foundation

/// One "user chose A, we recommended B" pair, broken down into the ranker's
/// own components rather than just the two final scores.
///
/// A miss on its own only says the ranking was wrong; it says nothing about
/// *which* weight to move. Carrying the per-component gap between the two
/// frames is what turns a pile of overrides into training data a later step
/// can fit personal weights against — without ever storing the photos, the
/// signals, or anything else that would make an example identifiable.
public struct BestShotOverrideExample: Codable, Sendable, Equatable {
    /// When the user made the pick.
    public let recordedAt: Date
    /// Which weight vector the cluster ranked under. Examples never cross
    /// branches: `faceQuality` is structurally 0 when the cluster has no
    /// faces, so mixing a faced example with a faceless one would teach the
    /// fit a relationship neither weight vector actually has.
    public let clusterHasFaces: Bool
    /// Chosen minus recommended, per component. The sufficient statistic for
    /// fitting weights: components do not depend on the weights, so nothing
    /// the pair holds is lost by storing only the difference.
    public let componentDelta: PhotoQualityScoringConfig.Weights
    /// Difference of `favoriteBonus - penalty` between the two frames — a
    /// fixed offset in the score that no weight can move, so the fit must
    /// carry it rather than absorb it.
    public let offsetDelta: Double
    /// The scoring formula the components were measured under. Examples from
    /// a different version are discarded rather than reinterpreted, the same
    /// way `PhotoQualityScore` treats its own `scoringModelVersion`.
    public let scoringModelVersion: Int

    public init(
        recordedAt: Date,
        clusterHasFaces: Bool,
        componentDelta: PhotoQualityScoringConfig.Weights,
        offsetDelta: Double,
        scoringModelVersion: Int
    ) {
        self.recordedAt = recordedAt
        self.clusterHasFaces = clusterHasFaces
        self.componentDelta = componentDelta
        self.offsetDelta = offsetDelta
        self.scoringModelVersion = scoringModelVersion
    }
}
