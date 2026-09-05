import Foundation

/// The device's personalized Best Shot weight vectors, fitted from the
/// user's own `BestShotOverrideExample`s.
///
/// Two vectors because the ranker itself branches on face presence: a
/// faceless cluster structurally zeroes `faceQuality`, so fitting one shared
/// vector would let the faceless branch's zero drag down the faced branch's
/// weight for a component it never actually measured.
public struct BestShotPersonalWeights: Codable, Sendable, Equatable {
    public let withFaces: PhotoQualityScoringConfig.Weights
    public let withoutFaces: PhotoQualityScoringConfig.Weights
    /// The formula these were fitted under; a mismatch discards them.
    public let scoringModelVersion: Int
    /// How many examples each branch was fitted from — the shrinkage input, kept
    /// so a debug screen or a test can say why the weights moved as little as they did.
    public let withFacesExampleCount: Int
    public let withoutFacesExampleCount: Int

    public init(
        withFaces: PhotoQualityScoringConfig.Weights,
        withoutFaces: PhotoQualityScoringConfig.Weights,
        scoringModelVersion: Int,
        withFacesExampleCount: Int,
        withoutFacesExampleCount: Int
    ) {
        self.withFaces = withFaces
        self.withoutFaces = withoutFaces
        self.scoringModelVersion = scoringModelVersion
        self.withFacesExampleCount = withFacesExampleCount
        self.withoutFacesExampleCount = withoutFacesExampleCount
    }
}
