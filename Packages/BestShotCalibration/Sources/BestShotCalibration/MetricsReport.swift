import Core
import Foundation

/// Offline calibration metrics computed by replaying `BestShotRanker.decide`
/// against a labelled corpus, once per cluster.
///
/// Every rate carries the cluster count it was computed over so a report never
/// reads a ratio out of a handful of clusters as if it were a solid measurement.
public struct MetricsReport: Equatable {
    public enum CategoryKey: Hashable, Comparable {
        case category(BestShotCalibrationCategory)
        case uncategorised

        public static func < (lhs: CategoryKey, rhs: CategoryKey) -> Bool {
            lhs.sortKey < rhs.sortKey
        }

        private var sortKey: String {
            switch self {
            case let .category(category): return category.rawValue
            case .uncategorised: return "zzz_uncategorised"
            }
        }

        public var displayName: String {
            switch self {
            case let .category(category): return category.rawValue
            case .uncategorised: return "uncategorised"
            }
        }
    }

    /// Metrics computed over one slice of the corpus (the whole corpus, or one
    /// category's clusters).
    public struct Bucket: Equatable, Sendable {
        public var clusterCount: Int
        public var automaticCount: Int
        public var lowConfidenceCount: Int
        public var unresolvedCount: Int

        /// Fraction of non-unresolved clusters where the ranker's pick matches
        /// the human label. `nil` when there are no resolved clusters to score.
        ///
        /// COVERAGE-DEPENDENT — DO NOT OPTIMISE THIS ALONE. Raising the
        /// resolution thresholds so more clusters become `.unresolved` can push
        /// this number up even when the ranker gets the exact same absolute
        /// number of clusters right, because the newly-unresolved clusters just
        /// stop being counted rather than being counted as wrong. Measured on a
        /// real 75-cluster corpus: bumping `absoluteSharpnessFloor` from 10 to
        /// 14 pushed 3 more clusters to `.unresolved` and raised this figure
        /// from 60.7% to 64.2% while `correctClusterCount` stayed at 34 of 75
        /// the whole time. Use `topOneAgreementOverAllClusters` (and
        /// `coverageRate`) as the optimisation target instead — see
        /// `WeightSweep.score`. This field still answers a real question
        /// ("when we do commit to a pick, how often are we right"), it just
        /// must never be read as "how good is the ranker" on its own.
        public var topOneAgreement: Double?
        public var resolvedClusterCount: Int

        /// Clusters where the ranker's pick equals `humanBestShotID`, counted
        /// over ALL clusters (an `.unresolved` cluster is not a pick, so it
        /// cannot be a match). The numerator behind
        /// `topOneAgreementOverAllClusters`.
        public var correctClusterCount: Int

        /// `correctClusterCount / clusterCount`: the fraction of the WHOLE
        /// corpus where the ranker both resolved and picked correctly. An
        /// unresolved cluster counts as a miss here, because the user got no
        /// recommendation at all — this is what makes the figure resistant to
        /// the "just refuse more often" trick that makes `topOneAgreement`
        /// unsafe to optimise directly. `nil` only when `clusterCount == 0`.
        public var topOneAgreementOverAllClusters: Double?

        /// Fraction of clusters that produced a recommendation at all
        /// (`1 - unresolvedRate`). Reported alongside the agreement figures so
        /// a trade-off between coverage and apparent accuracy is visible
        /// rather than hidden inside `topOneAgreement`.
        public var coverageRate: Double

        public var unresolvedRate: Double

        /// Fraction of clusters that produced a winner where that winner is
        /// clearly blurry by the ranker's own definition (critical sharpness
        /// ratio or below the absolute sharpness floor). `nil` when no cluster
        /// produced a winner.
        public var blurryWinnerRate: Double?
        public var winnerClusterCount: Int

        /// Over `.automatic` + `.lowConfidence` clusters, the fraction where the
        /// winner disagrees with the human label. This is an OFFLINE PROXY for
        /// the app's `BestShotOverrideMetrics.overrideRate` (which measures
        /// actual user overrides in the field) — not the same number, since no
        /// real user interaction is involved here.
        public var offlineOverrideProxy: Double?
        public var overrideEligibleClusterCount: Int

        static let empty = Bucket(
            clusterCount: 0,
            automaticCount: 0,
            lowConfidenceCount: 0,
            unresolvedCount: 0,
            topOneAgreement: nil,
            resolvedClusterCount: 0,
            correctClusterCount: 0,
            topOneAgreementOverAllClusters: nil,
            coverageRate: 0,
            unresolvedRate: 0,
            blurryWinnerRate: nil,
            winnerClusterCount: 0,
            offlineOverrideProxy: nil,
            overrideEligibleClusterCount: 0
        )
    }

    public var overall: Bucket
    /// Sorted by `CategoryKey` for deterministic report rendering.
    public var byCategory: [(key: CategoryKey, bucket: Bucket)]

    public static func == (lhs: MetricsReport, rhs: MetricsReport) -> Bool {
        guard lhs.overall == rhs.overall, lhs.byCategory.count == rhs.byCategory.count else { return false }
        for (l, r) in zip(lhs.byCategory, rhs.byCategory) where l.key != r.key || l.bucket != r.bucket {
            return false
        }
        return true
    }

    public static func compute(
        corpus: BestShotCalibrationCorpus,
        config: PhotoQualityScoringConfig
    ) -> MetricsReport {
        let outcomes = corpus.entries.map { cluster in
            ClusterOutcome(cluster: cluster, decision: decide(cluster: cluster, config: config))
        }

        let overall = bucket(from: outcomes, config: config)

        var grouped: [CategoryKey: [ClusterOutcome]] = [:]
        for outcome in outcomes {
            let key = outcome.cluster.category.map(CategoryKey.category) ?? .uncategorised
            grouped[key, default: []].append(outcome)
        }
        let byCategory = grouped
            .map { (key: $0.key, bucket: bucket(from: $0.value, config: config)) }
            .sorted { $0.key < $1.key }

        return MetricsReport(overall: overall, byCategory: byCategory)
    }

    private struct ClusterOutcome {
        let cluster: BestShotCalibrationCluster
        let decision: BestShotDecision
    }

    private static func decide(
        cluster: BestShotCalibrationCluster,
        config: PhotoQualityScoringConfig
    ) -> BestShotDecision {
        BestShotRanker.decide(
            snapshots: cluster.snapshots,
            scores: cluster.scores(
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion
            ),
            config: config
        )
    }

    private static func bucket(
        from outcomes: [ClusterOutcome],
        config: PhotoQualityScoringConfig
    ) -> Bucket {
        guard !outcomes.isEmpty else { return .empty }

        var automaticCount = 0
        var lowConfidenceCount = 0
        var unresolvedCount = 0
        var resolvedAgreements = 0
        var resolvedCount = 0
        var correctCount = 0
        var winnerCount = 0
        var blurryWinnerCount = 0
        var overrideEligibleCount = 0
        var overrideDisagreementCount = 0

        for outcome in outcomes {
            let decision = outcome.decision
            switch decision.confidence {
            case .automatic: automaticCount += 1
            case .lowConfidence: lowConfidenceCount += 1
            case .unresolved: unresolvedCount += 1
            }

            if decision.confidence != .unresolved {
                resolvedCount += 1
                if decision.localIdentifier == outcome.cluster.humanBestShotID {
                    resolvedAgreements += 1
                }
            }

            if decision.localIdentifier == outcome.cluster.humanBestShotID {
                correctCount += 1
            }

            if let winner = decision.localIdentifier {
                winnerCount += 1
                if isBlurryWinner(winner, cluster: outcome.cluster, config: config) {
                    blurryWinnerCount += 1
                }

                if decision.confidence == .automatic || decision.confidence == .lowConfidence {
                    overrideEligibleCount += 1
                    if winner != outcome.cluster.humanBestShotID {
                        overrideDisagreementCount += 1
                    }
                }
            }
        }

        let total = outcomes.count
        return Bucket(
            clusterCount: total,
            automaticCount: automaticCount,
            lowConfidenceCount: lowConfidenceCount,
            unresolvedCount: unresolvedCount,
            topOneAgreement: resolvedCount > 0 ? Double(resolvedAgreements) / Double(resolvedCount) : nil,
            resolvedClusterCount: resolvedCount,
            correctClusterCount: correctCount,
            topOneAgreementOverAllClusters: total > 0 ? Double(correctCount) / Double(total) : nil,
            coverageRate: 1 - Double(unresolvedCount) / Double(total),
            unresolvedRate: Double(unresolvedCount) / Double(total),
            blurryWinnerRate: winnerCount > 0 ? Double(blurryWinnerCount) / Double(winnerCount) : nil,
            winnerClusterCount: winnerCount,
            offlineOverrideProxy: overrideEligibleCount > 0
                ? Double(overrideDisagreementCount) / Double(overrideEligibleCount)
                : nil,
            overrideEligibleClusterCount: overrideEligibleCount
        )
    }

    /// Uses `BestShotRanker.sharpnessRatios` — the ranker's own definition of
    /// "clearly blurry" — rather than re-deriving the ratio here, so this can
    /// never quietly drift from what `decide` itself excludes on.
    private static func isBlurryWinner(
        _ winner: String,
        cluster: BestShotCalibrationCluster,
        config: PhotoQualityScoringConfig
    ) -> Bool {
        let scores = cluster.scores(
            scoringModelVersion: config.scoringModelVersion,
            thumbnailConfigVersion: config.thumbnailConfigVersion
        )
        let ratios = BestShotRanker.sharpnessRatios(
            snapshots: cluster.snapshots,
            scores: scores,
            config: config
        )
        let ratio = ratios[winner] ?? 1
        let globalSharpness = scores[winner]?.signals.globalSharpness ?? .infinity
        return ratio < config.criticalSharpnessRatio || globalSharpness < config.absoluteSharpnessFloor
    }
}
