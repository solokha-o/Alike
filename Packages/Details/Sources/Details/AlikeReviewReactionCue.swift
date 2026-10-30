import Foundation

struct AlikeReviewReactionCue: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let clusterID: UUID
        let generation: Int
    }

    let id: ID
}
