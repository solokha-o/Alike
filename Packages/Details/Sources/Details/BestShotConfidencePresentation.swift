import Core
import SwiftUI

/// Presentation of the Best Shot ranking: how sure it is, and why it picked
/// this photo. Kept next to the details screen because the wording is UI copy,
/// not part of the ranking model.
extension BestShotReasonCode {
    var localizedLabel: String {
        switch self {
        case .sharper:
            return DetailsL10n.ClusterDetails.reasonSharper
        case .betterExposure:
            return DetailsL10n.ClusterDetails.reasonBetterExposure
        case .faceInFocus:
            return DetailsL10n.ClusterDetails.reasonFaceInFocus
        case .openEyes:
            return DetailsL10n.ClusterDetails.reasonOpenEyes
        case .lessNoise:
            return DetailsL10n.ClusterDetails.reasonLessNoise
        case .favorite:
            return DetailsL10n.ClusterDetails.favorite
        case .higherResolution:
            return DetailsL10n.ClusterDetails.reasonHigherResolution
        }
    }
}

extension BestShotConfidence {
    /// The badge title. `.unresolved` has no badge at all, so it falls back to
    /// the neutral label.
    var badgeTitle: String {
        switch self {
        case .automatic:
            return DetailsL10n.Common.bestShot
        case .lowConfidence:
            return DetailsL10n.ClusterDetails.probablyBestShot
        case .unresolved:
            return DetailsL10n.Common.bestShot
        }
    }

    var badgeSymbolName: String {
        switch self {
        case .automatic:
            return "star.fill"
        case .lowConfidence:
            return "star.leadinghalf.filled"
        case .unresolved:
            return "questionmark.circle"
        }
    }
}

/// Joins the reason codes into one short line, e.g. "Sharper · Face in focus".
enum BestShotReasonSummary {
    static let separator = " · "

    static func text(for reasonCodes: [BestShotReasonCode]) -> String? {
        guard !reasonCodes.isEmpty else { return nil }
        return reasonCodes.map(\.localizedLabel).joined(separator: separator)
    }
}
