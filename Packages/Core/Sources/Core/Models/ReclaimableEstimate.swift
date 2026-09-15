import Foundation
import Photos

/// One asset as the reclaimable estimate sees it: its identity and the bytes the
/// app expects to get back by deleting it.
public struct ReclaimableAsset: Hashable, Sendable {
    public let localIdentifier: String
    public let estimatedCleanupBytes: Int64

    public init(localIdentifier: String, estimatedCleanupBytes: Int64) {
        self.localIdentifier = localIdentifier
        self.estimatedCleanupBytes = estimatedCleanupBytes
    }
}

/// A cluster of similar photos reduced to what the estimate needs: its assets and
/// the one the user keeps. The keeper is never counted as reclaimable.
public struct ReclaimableCluster: Equatable, Sendable {
    public let assets: [ReclaimableAsset]
    public let keeperLocalIdentifier: String?

    public init(assets: [ReclaimableAsset], keeperLocalIdentifier: String?) {
        self.assets = assets
        self.keeperLocalIdentifier = keeperLocalIdentifier
    }
}

/// A cleanup category (screenshots, blurred photos) reduced to the identifiers it
/// proposes and the bytes it already summed over them.
public struct ReclaimableCategory: Equatable, Sendable {
    public let localIdentifiers: [String]
    public let estimatedSavingsBytes: Int64

    public init(localIdentifiers: [String], estimatedSavingsBytes: Int64) {
        self.localIdentifiers = localIdentifiers
        self.estimatedSavingsBytes = estimatedSavingsBytes
    }
}

/// The "reclaimable" figure the scanner card, the post-scan premium offer and the
/// widget all show. Every consumer reads this value; none recomputes it.
public struct ReclaimableEstimate: Equatable, Sendable {
    /// Bytes of the non-keeper assets across all clusters, each asset once.
    public let clusterBytes: Int64
    /// Bytes the categories propose, minus whatever the clusters already counted.
    public let categoryBytes: Int64

    public var totalBytes: Int64 { clusterBytes + categoryBytes }

    public init(clusterBytes: Int64, categoryBytes: Int64) {
        self.clusterBytes = clusterBytes
        self.categoryBytes = categoryBytes
    }

    public static let zero = ReclaimableEstimate(clusterBytes: 0, categoryBytes: 0)
}

/// The single place the reclaimable figure is computed.
///
/// Rule: every `localIdentifier` is counted at most once, and a cluster's keeper is
/// not counted at all.
///
/// 1. Clusters contribute their non-keeper assets, deduplicated by identifier, so an
///    asset that landed in two clusters is one asset.
/// 2. Categories contribute their own recorded sum, minus the bytes of any of their
///    identifiers a cluster already counted. A screenshot that also sits in a cluster
///    is therefore one screenshot, not two. The subtraction uses the cluster's bytes
///    for that asset — the same ``AssetByteSize`` source the category sum was built
///    from (a heuristic snapshot is re-measured on load) — and a category never goes
///    below zero.
/// 3. A keeper that is also a category candidate stays in the category: the cluster
///    does not count it, the category does, so it is still counted exactly once.
public enum ReclaimableEstimateCalculator {
    public static func estimate(
        clusters: [ReclaimableCluster],
        categories: [ReclaimableCategory]
    ) -> ReclaimableEstimate {
        var countedBytesByIdentifier: [String: Int64] = [:]
        countedBytesByIdentifier.reserveCapacity(clusters.reduce(0) { $0 + $1.assets.count })

        for cluster in clusters {
            for asset in cluster.assets where asset.localIdentifier != cluster.keeperLocalIdentifier {
                if countedBytesByIdentifier[asset.localIdentifier] == nil {
                    countedBytesByIdentifier[asset.localIdentifier] = asset.estimatedCleanupBytes
                }
            }
        }
        let clusterBytes = countedBytesByIdentifier.values.reduce(into: Int64(0)) { $0 += $1 }

        let categoryBytes = categories.reduce(into: Int64(0)) { total, category in
            let alreadyCounted = category.localIdentifiers.reduce(into: Int64(0)) { partial, identifier in
                partial += countedBytesByIdentifier[identifier] ?? 0
            }
            total += max(0, category.estimatedSavingsBytes - alreadyCounted)
        }

        return ReclaimableEstimate(clusterBytes: clusterBytes, categoryBytes: categoryBytes)
    }
}

public extension PhotoCluster {
    /// The cluster as the reclaimable estimate sees it.
    ///
    /// - Parameter preferredKeeperLocalIdentifier: The user's reviewed best shot, when
    ///   one is known. It wins over the computed pick, exactly as it does on screen.
    func reclaimableCluster(keeping preferredKeeperLocalIdentifier: String? = nil) -> ReclaimableCluster {
        ReclaimableCluster(
            assets: assets.map {
                ReclaimableAsset(
                    localIdentifier: $0.localIdentifier,
                    estimatedCleanupBytes: $0.estimatedCleanupBytes
                )
            },
            keeperLocalIdentifier: bestShotAsset(preferring: preferredKeeperLocalIdentifier)?.localIdentifier
        )
    }
}

public extension CleanupCategorySnapshot {
    /// The category as the reclaimable estimate sees it.
    var reclaimableCategory: ReclaimableCategory {
        ReclaimableCategory(
            localIdentifiers: localIdentifiers,
            estimatedSavingsBytes: estimatedSavingsBytes
        )
    }
}
