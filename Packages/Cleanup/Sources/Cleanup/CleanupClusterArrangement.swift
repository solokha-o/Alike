import Core
import Foundation

/// A cluster paired with an identity that survives a reconciliation rescan.
///
/// ``PhotoCluster/id`` is minted fresh on every scan, so using it as the
/// `ForEach` identity tears down and rebuilds the whole grid whenever Cleanup
/// reconciles after a deletion. ``PhotoCluster/contentKey`` is derived from the
/// cluster's assets instead, which is the same key
/// ``ClusterReviewStateResurfacer`` already matches old clusters to new ones on.
struct IdentifiedCluster: Identifiable, Equatable {
    /// `contentKey`, suffixed with an occurrence index so two clusters that
    /// happen to share content still get distinct identities. `ForEach` silently
    /// drops duplicate ids, so this must never collide.
    let id: String
    let cluster: PhotoCluster

    static func == (lhs: IdentifiedCluster, rhs: IdentifiedCluster) -> Bool {
        lhs.id == rhs.id && lhs.cluster.id == rhs.cluster.id
    }
}

/// The sorted, filtered and sectioned cluster list rendered by `CleanupView`.
///
/// This is a snapshot rather than a derived-on-every-body-pass value on purpose.
/// `ClusterDetailsView` reports review progress back to the host while it is
/// still pushed, and re-deriving the order there would reorder, re-filter and
/// migrate rows underneath the user, so the scroll offset no longer points at
/// the row they came from. Cleanup refreshes the arrangement when it is the
/// visible screen instead; review badges still update live because the cards
/// read status straight from the workspace.
struct CleanupClusterArrangement: Equatable {
    var needsReview: [IdentifiedCluster] = []
    var remaining: [IdentifiedCluster] = []
    var hasAnyCluster = false

    /// True when clusters exist but the current controls hide all of them.
    var isEmptyAfterFiltering: Bool {
        hasAnyCluster && needsReview.isEmpty && remaining.isEmpty
    }

    static func make(
        clusters: [PhotoCluster],
        controls: CleanupClusterControls,
        appliesAdvancedFilters: Bool,
        reviewStatus: (UUID) -> ClusterReviewStatus,
        estimatedSavings: (UUID) -> Int64
    ) -> CleanupClusterArrangement {
        let sorted = clusters.sorted { lhs, rhs in
            switch controls.sort {
            case .newest: lhs.createdAt > rhs.createdAt
            case .largestCluster: lhs.count > rhs.count
            case .similarity: lhs.averageSimilarity > rhs.averageSimilarity
            case .reviewStatus: reviewStatus(lhs.id).rawValue < reviewStatus(rhs.id).rawValue
            case .largestCleanupOpportunity: estimatedSavings(lhs.id) > estimatedSavings(rhs.id)
            }
        }

        let visible = appliesAdvancedFilters
            ? sorted.filter { controls.matches($0, reviewStatus: reviewStatus($0.id)) }
            : sorted

        var occurrences: [String: Int] = [:]
        var needsReview: [IdentifiedCluster] = []
        var remaining: [IdentifiedCluster] = []

        for cluster in visible {
            let key = cluster.contentKey
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            let identified = IdentifiedCluster(
                cluster: cluster,
                contentKey: key,
                occurrence: occurrence
            )

            if reviewStatus(cluster.id) == .needsReReview {
                needsReview.append(identified)
            } else {
                remaining.append(identified)
            }
        }

        return CleanupClusterArrangement(
            needsReview: needsReview,
            remaining: remaining,
            hasAnyCluster: !clusters.isEmpty
        )
    }

    /// Every row id in the order they are rendered, top section first.
    var orderedIDs: [String] {
        needsReview.map(\.id) + remaining.map(\.id)
    }

    /// The scroll anchor to keep when this arrangement replaces `previous`.
    ///
    /// Reconciliation after a deletion changes the affected cluster's contents,
    /// so its ``IdentifiedCluster/id`` changes too — and if that row was the
    /// anchor, `scrollPosition` has nothing left to pin and the grid slides. In
    /// that case fall back to the nearest surviving neighbour, preferring the
    /// row below because that is what moves up into the anchor's old position.
    func preservedAnchor(
        _ anchor: String?,
        replacing previous: CleanupClusterArrangement
    ) -> String? {
        guard let anchor else { return nil }

        let surviving = Set(orderedIDs)
        if surviving.contains(anchor) { return anchor }

        let previousOrder = previous.orderedIDs
        guard let index = previousOrder.firstIndex(of: anchor) else { return nil }

        for offset in 1...max(previousOrder.count, 1) {
            let below = index + offset
            if below < previousOrder.count, surviving.contains(previousOrder[below]) {
                return previousOrder[below]
            }
            let above = index - offset
            if above >= 0, surviving.contains(previousOrder[above]) {
                return previousOrder[above]
            }
        }

        return nil
    }
}

private extension IdentifiedCluster {
    init(cluster: PhotoCluster, contentKey: String, occurrence: Int) {
        self.id = occurrence == 0 ? contentKey : "\(contentKey)#\(occurrence)"
        self.cluster = cluster
    }
}
