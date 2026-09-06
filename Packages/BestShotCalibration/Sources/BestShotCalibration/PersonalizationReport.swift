import Core
import Foundation

/// Offline regression guard for Best Shot personalisation: fits personal
/// weights from a prefix of the corpus and checks whether they ever make the
/// ranking *worse* on the clusters that were held out.
///
/// This answers one question — "does personalisation ever hurt?" — not
/// "how much does it help". A clean pass here is a floor, not a demonstration
/// of gain.
public enum PersonalizationReport {
    // MARK: - Prefix parsing

    public enum PrefixParseError: Error, CustomStringConvertible, Equatable {
        case invalidToken(String)

        public var description: String {
            switch self {
            case let .invalidToken(token):
                return "Invalid --prefix value '\(token)': expected a non-negative integer or 'all'."
            }
        }
    }

    public static let defaultPrefixSpec = "10,30,100,all"

    /// Parses a comma-separated `--prefix` value such as `"10,30,100,all"`
    /// into concrete prefix sizes. `"all"` resolves to `corpusSize`. Every
    /// size is clamped into `0...corpusSize` and duplicates (including ones
    /// created by clamping) collapse, so the result is sorted ascending with
    /// no repeats.
    public static func parsePrefixes(_ raw: String, corpusSize: Int) throws -> [Int] {
        let tokens = raw
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var sizes: Set<Int> = []
        for token in tokens {
            if token == "all" {
                sizes.insert(corpusSize)
            } else if let value = Int(token), value >= 0 {
                sizes.insert(min(value, corpusSize))
            } else {
                throw PrefixParseError.invalidToken(token)
            }
        }
        return sizes.sorted()
    }

    // MARK: - Fold-count parsing

    public enum FoldsParseError: Error, CustomStringConvertible, Equatable {
        case invalidValue(String)
        case outOfRange(Int, corpusSize: Int)

        public var description: String {
            switch self {
            case let .invalidValue(token):
                return "Invalid --folds value '\(token)': expected an integer >= 2."
            case let .outOfRange(value, corpusSize):
                return "Invalid --folds value \(value): must be between 2 and the corpus size "
                    + "(\(corpusSize) cluster(s))."
            }
        }
    }

    public static let defaultFolds = 5

    /// Parses a `--folds` value. Valid range is `2...corpusSize` — below 2
    /// there is no held-out set, and above the corpus size a fold would be
    /// empty. Unlike `--prefix`, an out-of-range value is rejected rather
    /// than silently clamped: a fold count the corpus cannot support is a
    /// configuration error, not a size to shrink to.
    public static func parseFolds(_ raw: String, corpusSize: Int) throws -> Int {
        guard let value = Int(raw.trimmingCharacters(in: .whitespaces)) else {
            throw FoldsParseError.invalidValue(raw)
        }
        guard value >= 2, value <= corpusSize else {
            throw FoldsParseError.outOfRange(value, corpusSize: corpusSize)
        }
        return value
    }

    // MARK: - Fixed timestamp

    /// Stand-in for `BestShotOverrideExample.recordedAt`. The corpus was
    /// labelled in one sitting, not accumulated over time the way real
    /// overrides are, so a per-cluster timestamp here would be fiction. Fit
    /// order is by `clusterID`, never by this date.
    public static let fixedRecordedAt = Date(timeIntervalSince1970: 0)

    // MARK: - Result shape

    /// What happened while turning a fit-set slice into override examples.
    public struct FitOutcome: Equatable, Sendable {
        public var fitClusterCount: Int
        /// The ranker's winner already matched the human label: no
        /// disagreement, nothing to synthesise.
        public var agreementClusterCount: Int
        /// The ranker produced no winner at all (`.unresolved`): there is no
        /// "winner" to disagree with the human label.
        public var unresolvedClusterCount: Int
        /// The ranker's winner disagreed with the human label, but
        /// `BestShotRanker.overrideExample` still returned `nil` (clamped
        /// score, or fewer than two usable candidates). A fit set that mostly
        /// lands here is a finding about the corpus, not a bug in this tool.
        public var refusedExampleCount: Int
        public var exampleCount: Int
        public var withFacesExampleCount: Int
        public var withoutFacesExampleCount: Int
    }

    /// Everything computed for one `--prefix` value.
    public struct PrefixResult: Equatable, Sendable {
        public var prefixSize: Int
        public var fit: FitOutcome
        /// `clusterID`, sorted, of every cluster in the fit set.
        public var fitClusterIDs: [String]
        /// `clusterID`, sorted, of every cluster in the eval set. Always
        /// disjoint from `fitClusterIDs` by construction (they are two slices
        /// of the same ordered list).
        public var evalClusterIDs: [String]
        public var personalizedConfig: PhotoQualityScoringConfig
        /// `false` when the with-faces branch's fit came back identical to
        /// the global weights — either it never reached the minimum example
        /// count, or the fit had nothing to work with in the first place.
        public var withFacesEngaged: Bool
        /// Same as `withFacesEngaged`, for the without-faces branch.
        public var withoutFacesEngaged: Bool
        /// `nil` when the fit set is the whole corpus and there is nothing
        /// left to evaluate on.
        public var baseline: MetricsReport.Bucket?
        public var personalized: MetricsReport.Bucket?

        public var evalClusterCount: Int { evalClusterIDs.count }
        /// `true` when either branch moved away from the global weights.
        public var personalizationEngaged: Bool { withFacesEngaged || withoutFacesEngaged }
    }

    public struct Result: Equatable, Sendable {
        public var prefixResults: [PrefixResult]
    }

    // MARK: - K-fold result shape

    /// Running sum of `MetricsReport.Bucket` counts across every eval fold,
    /// so the aggregate rate is computed over the whole corpus rather than by
    /// averaging per-fold rates (which would let a small fold's noise count
    /// as much as a large one's).
    public struct AggregateBucket: Equatable, Sendable {
        public var clusterCount: Int
        public var correctClusterCount: Int
        public var unresolvedCount: Int
        public var winnerClusterCount: Int
        public var blurryWinnerCount: Int

        public static let zero = AggregateBucket(
            clusterCount: 0,
            correctClusterCount: 0,
            unresolvedCount: 0,
            winnerClusterCount: 0,
            blurryWinnerCount: 0
        )

        public var topOneAgreementOverAllClusters: Double? {
            clusterCount > 0 ? Double(correctClusterCount) / Double(clusterCount) : nil
        }

        public var coverageRate: Double? {
            clusterCount > 0 ? 1 - Double(unresolvedCount) / Double(clusterCount) : nil
        }

        public var blurryWinnerRate: Double? {
            winnerClusterCount > 0 ? Double(blurryWinnerCount) / Double(winnerClusterCount) : nil
        }

        static func + (lhs: AggregateBucket, rhs: MetricsReport.Bucket) -> AggregateBucket {
            AggregateBucket(
                clusterCount: lhs.clusterCount + rhs.clusterCount,
                correctClusterCount: lhs.correctClusterCount + rhs.correctClusterCount,
                unresolvedCount: lhs.unresolvedCount + rhs.unresolvedCount,
                winnerClusterCount: lhs.winnerClusterCount + rhs.winnerClusterCount,
                blurryWinnerCount: lhs.blurryWinnerCount + rhs.blurryWinnerCount
            )
        }
    }

    /// Everything computed for one fold: fit on the other k-1 folds,
    /// evaluate on this one.
    public struct FoldResult: Equatable, Sendable {
        public var foldIndex: Int
        public var fit: FitOutcome
        public var fitClusterIDs: [String]
        public var evalClusterIDs: [String]
        public var personalizedConfig: PhotoQualityScoringConfig
        public var withFacesEngaged: Bool
        public var withoutFacesEngaged: Bool
        public var baseline: MetricsReport.Bucket?
        public var personalized: MetricsReport.Bucket?

        public var evalClusterCount: Int { evalClusterIDs.count }
    }

    public struct KFoldResult: Equatable, Sendable {
        public var folds: Int
        public var foldResults: [FoldResult]
        public var aggregateBaseline: AggregateBucket
        public var aggregatePersonalized: AggregateBucket
        /// `true` if the with-faces branch engaged in at least one fold.
        public var withFacesEngagedAnyFold: Bool
        /// `true` if the without-faces branch engaged in at least one fold.
        public var withoutFacesEngagedAnyFold: Bool
        /// How many corpus clusters (out of the whole corpus, not just one
        /// fold) carry at least one measured face — reported so a branch
        /// that never engages can be explained rather than left as a mystery.
        public var faceBearingClusterCount: Int
    }

    // MARK: - Entry point

    /// Orders `corpus.entries` deterministically by `clusterID` — the corpus
    /// carries no reliable chronological signal, so this is the one order
    /// every prefix size is measured against.
    public static func orderedClusters(of corpus: BestShotCalibrationCorpus) -> [BestShotCalibrationCluster] {
        corpus.entries.sorted { $0.clusterID < $1.clusterID }
    }

    public static func run(
        corpus: BestShotCalibrationCorpus,
        prefixSizes: [Int],
        global: PhotoQualityScoringConfig = .current
    ) -> Result {
        let ordered = orderedClusters(of: corpus)
        let results = prefixSizes.map { size in
            evaluate(prefixSize: min(max(size, 0), ordered.count), ordered: ordered, global: global)
        }
        return Result(prefixResults: results)
    }

    // MARK: - K-fold entry point

    /// Fits on k-1 folds and evaluates on the held-out fold, for every fold
    /// in turn — unlike the prefix curve, every row here can both reach the
    /// fit minimum (enough clusters in k-1 folds to engage personalisation)
    /// and measure the result on clusters the fit never saw.
    ///
    /// Fold membership is deterministic: clusters sorted by `clusterID` (see
    /// `orderedClusters`), fold `= index % folds`. The same sort the prefix
    /// mode uses, so the two views agree on cluster ordering even though
    /// they slice it differently.
    public static func runKFold(
        corpus: BestShotCalibrationCorpus,
        folds: Int,
        global: PhotoQualityScoringConfig = .current
    ) -> KFoldResult {
        precondition(folds >= 2, "folds must be >= 2, got \(folds)")
        let ordered = orderedClusters(of: corpus)
        let indexed = Array(ordered.enumerated())

        var foldResults: [FoldResult] = []
        var aggregateBaseline = AggregateBucket.zero
        var aggregatePersonalized = AggregateBucket.zero
        var withFacesEngagedAnyFold = false
        var withoutFacesEngagedAnyFold = false

        for foldIndex in 0..<folds {
            let evalEntries = indexed.filter { $0.offset % folds == foldIndex }.map(\.element)
            let fitEntries = indexed.filter { $0.offset % folds != foldIndex }.map(\.element)

            let split = evaluateSplit(fitEntries: fitEntries, evalEntries: evalEntries, global: global)
            if split.withFacesEngaged { withFacesEngagedAnyFold = true }
            if split.withoutFacesEngaged { withoutFacesEngagedAnyFold = true }
            if let baseline = split.baseline { aggregateBaseline = aggregateBaseline + baseline }
            if let personalized = split.personalized { aggregatePersonalized = aggregatePersonalized + personalized }

            foldResults.append(FoldResult(
                foldIndex: foldIndex,
                fit: split.fit,
                fitClusterIDs: fitEntries.map(\.clusterID),
                evalClusterIDs: evalEntries.map(\.clusterID),
                personalizedConfig: split.personalizedConfig,
                withFacesEngaged: split.withFacesEngaged,
                withoutFacesEngaged: split.withoutFacesEngaged,
                baseline: split.baseline,
                personalized: split.personalized
            ))
        }

        let faceBearingClusterCount = ordered.filter { cluster in
            cluster.candidates.contains { $0.signals.hasFaces }
        }.count

        return KFoldResult(
            folds: folds,
            foldResults: foldResults,
            aggregateBaseline: aggregateBaseline,
            aggregatePersonalized: aggregatePersonalized,
            withFacesEngagedAnyFold: withFacesEngagedAnyFold,
            withoutFacesEngagedAnyFold: withoutFacesEngagedAnyFold,
            faceBearingClusterCount: faceBearingClusterCount
        )
    }

    // MARK: - Shared fit/eval split

    /// What one fit set produces, whether it came from a prefix or a fold:
    /// the fitted config, whether each branch actually moved, and the
    /// baseline/personalized metrics on whatever was held out.
    private struct SplitResult {
        var fit: FitOutcome
        var personalizedConfig: PhotoQualityScoringConfig
        var withFacesEngaged: Bool
        var withoutFacesEngaged: Bool
        var baseline: MetricsReport.Bucket?
        var personalized: MetricsReport.Bucket?
    }

    /// Fits on `fitEntries` and, when `evalEntries` is non-empty, measures
    /// both the baseline and personalized config on it. Shared by the prefix
    /// and k-fold modes so they can never quietly diverge on what "fit" or
    /// "evaluate" means.
    private static func evaluateSplit(
        fitEntries: [BestShotCalibrationCluster],
        evalEntries: [BestShotCalibrationCluster],
        global: PhotoQualityScoringConfig
    ) -> SplitResult {
        let fitBuild = fitExamples(from: fitEntries, config: global)
        let personalWeights = PersonalWeightModel.personalWeights(from: fitBuild.examples, global: global)

        var personalizedConfig = global
        personalizedConfig.weightsWithFaces = personalWeights.withFaces
        personalizedConfig.weightsWithoutFaces = personalWeights.withoutFaces

        let withFacesEngaged = personalizedConfig.weightsWithFaces != global.weightsWithFaces
        let withoutFacesEngaged = personalizedConfig.weightsWithoutFaces != global.weightsWithoutFaces

        var baseline: MetricsReport.Bucket?
        var personalized: MetricsReport.Bucket?
        if !evalEntries.isEmpty {
            let evalCorpus = BestShotCalibrationCorpus(
                exportedAt: Date(timeIntervalSince1970: 0),
                scoringModelVersion: global.scoringModelVersion,
                thumbnailConfigVersion: global.thumbnailConfigVersion,
                entries: evalEntries
            )
            baseline = MetricsReport.compute(corpus: evalCorpus, config: global).overall
            personalized = MetricsReport.compute(corpus: evalCorpus, config: personalizedConfig).overall
        }

        return SplitResult(
            fit: fitBuild.outcome,
            personalizedConfig: personalizedConfig,
            withFacesEngaged: withFacesEngaged,
            withoutFacesEngaged: withoutFacesEngaged,
            baseline: baseline,
            personalized: personalized
        )
    }

    // MARK: - Per-prefix evaluation

    private static func evaluate(
        prefixSize: Int,
        ordered: [BestShotCalibrationCluster],
        global: PhotoQualityScoringConfig
    ) -> PrefixResult {
        let fitEntries = Array(ordered.prefix(prefixSize))
        let evalEntries = Array(ordered.dropFirst(prefixSize))

        let split = evaluateSplit(fitEntries: fitEntries, evalEntries: evalEntries, global: global)

        return PrefixResult(
            prefixSize: prefixSize,
            fit: split.fit,
            fitClusterIDs: fitEntries.map(\.clusterID),
            evalClusterIDs: evalEntries.map(\.clusterID),
            personalizedConfig: split.personalizedConfig,
            withFacesEngaged: split.withFacesEngaged,
            withoutFacesEngaged: split.withoutFacesEngaged,
            baseline: split.baseline,
            personalized: split.personalized
        )
    }

    // MARK: - Fit-set synthesis

    /// Internal (not `private`) so `@testable import` can verify a
    /// synthesised example matches a direct `BestShotRanker.overrideExample`
    /// call for the same cluster, without duplicating the fit logic in tests.
    struct FitBuild {
        var examples: [BestShotOverrideExample]
        var outcome: FitOutcome
    }

    /// Replays `BestShotRanker.decide` over the fit-set clusters and turns
    /// every disagreement with `humanBestShotID` into an override example via
    /// `BestShotRanker.overrideExample`, exactly as a real in-app override
    /// would be captured.
    static func fitExamples(
        from entries: [BestShotCalibrationCluster],
        config: PhotoQualityScoringConfig
    ) -> FitBuild {
        var examples: [BestShotOverrideExample] = []
        var agreementCount = 0
        var unresolvedCount = 0
        var refusedCount = 0

        for cluster in entries {
            let scores = cluster.scores(
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion
            )
            let decision = BestShotRanker.decide(snapshots: cluster.snapshots, scores: scores, config: config)

            guard let winner = decision.localIdentifier else {
                // No winner at all: there is nothing to disagree with the
                // human label, so this cluster contributes no example.
                unresolvedCount += 1
                continue
            }
            guard winner != cluster.humanBestShotID else {
                agreementCount += 1
                continue
            }

            guard let example = BestShotRanker.overrideExample(
                snapshots: cluster.snapshots,
                scores: scores,
                chosen: cluster.humanBestShotID,
                recommended: winner,
                now: fixedRecordedAt,
                config: config
            ) else {
                refusedCount += 1
                continue
            }
            examples.append(example)
        }

        let withFaces = examples.filter(\.clusterHasFaces).count
        let outcome = FitOutcome(
            fitClusterCount: entries.count,
            agreementClusterCount: agreementCount,
            unresolvedClusterCount: unresolvedCount,
            refusedExampleCount: refusedCount,
            exampleCount: examples.count,
            withFacesExampleCount: withFaces,
            withoutFacesExampleCount: examples.count - withFaces
        )
        return FitBuild(examples: examples, outcome: outcome)
    }
}
