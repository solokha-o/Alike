import Foundation

/// How much the ranking trusts its own pick.
public enum BestShotConfidence: String, Codable, Sendable, Equatable {
    /// Clear winner: the badge is shown as usual.
    case automatic
    /// A winner exists but the lead is thin, so the UI says "probably best".
    case lowConfidence
    /// No honest recommendation: the user picks.
    case unresolved
}

/// Short, user-facing explanation of why the winner won.
public enum BestShotReasonCode: String, Codable, Sendable, Equatable, CaseIterable {
    case sharper
    case betterExposure
    case faceInFocus
    case openEyes
    case lessNoise
    case favorite
    case higherResolution
}

/// One scored candidate, kept so the UI and the tests can inspect the order.
public struct BestShotCandidate: Codable, Sendable, Equatable {
    public let localIdentifier: String
    public let score: Double
    /// `true` when the candidate was dropped before ranking (critical blur next
    /// to a sharp reference frame, or an asset that could not be measured).
    public let isExcluded: Bool
    public let hasQualitySignals: Bool

    public init(
        localIdentifier: String,
        score: Double,
        isExcluded: Bool,
        hasQualitySignals: Bool
    ) {
        self.localIdentifier = localIdentifier
        self.score = score
        self.isExcluded = isExcluded
        self.hasQualitySignals = hasQualitySignals
    }
}

/// The outcome of ranking one cluster.
public struct BestShotDecision: Codable, Sendable, Equatable {
    /// `nil` only for `.unresolved`, and for an empty cluster.
    public let localIdentifier: String?
    public let confidence: BestShotConfidence
    public let topScore: Double
    public let margin: Double
    public let reasonCodes: [BestShotReasonCode]
    public let rankedCandidates: [BestShotCandidate]

    public init(
        localIdentifier: String?,
        confidence: BestShotConfidence,
        topScore: Double,
        margin: Double,
        reasonCodes: [BestShotReasonCode],
        rankedCandidates: [BestShotCandidate]
    ) {
        self.localIdentifier = localIdentifier
        self.confidence = confidence
        self.topScore = topScore
        self.margin = margin
        self.reasonCodes = reasonCodes
        self.rankedCandidates = rankedCandidates
    }

    public static let empty = BestShotDecision(
        localIdentifier: nil,
        confidence: .unresolved,
        topScore: 0,
        margin: 0,
        reasonCodes: [],
        rankedCandidates: []
    )

    /// The identifier to rank on even when confidence is too low to show a
    /// badge — the deterministic head of the ranking.
    public var rankedLeaderIdentifier: String? {
        localIdentifier ?? rankedCandidates.first(where: { !$0.isExcluded })?.localIdentifier
    }
}
