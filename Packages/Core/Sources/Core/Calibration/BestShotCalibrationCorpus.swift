import Foundation

/// A locally labelled corpus for calibrating Best Shot scoring weights offline.
///
/// The in-app exporter and the offline calibration CLI share this one schema so
/// neither side can drift from the other's idea of a cluster or a candidate.
/// `assetID` is a salted, per-export opaque string rather than a PhotoKit
/// `localIdentifier`: the exported file is meant to leave the device and be
/// read by a CLI on a developer's Mac, so it must not carry PhotoKit identity
/// that could re-identify the user's library.
///
/// Production scoring is untouched by this type: it only carries the raw
/// signals and metadata the ranker already consumes, plus the human label the
/// harness scores its candidate weights against.
public struct BestShotCalibrationCorpus: Codable, Sendable, Equatable {
    /// Bumped whenever a field is removed or its meaning changes. New optional
    /// fields do not need a bump — `Codable`'s defaulted decoding handles those
    /// — which is why decoding tolerates an unknown, higher version instead of
    /// rejecting it outright.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var exportedAt: Date
    /// The scoring model and thumbnail config versions in effect when this
    /// corpus was exported, so the harness can tell a stale export from a
    /// current one without re-deriving it from the entries.
    public var scoringModelVersion: Int
    public var thumbnailConfigVersion: Int
    public var entries: [BestShotCalibrationCluster]

    public init(
        schemaVersion: Int = BestShotCalibrationCorpus.currentSchemaVersion,
        exportedAt: Date,
        scoringModelVersion: Int,
        thumbnailConfigVersion: Int,
        entries: [BestShotCalibrationCluster]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.scoringModelVersion = scoringModelVersion
        self.thumbnailConfigVersion = thumbnailConfigVersion
        self.entries = entries
    }
}

/// One labelled cluster: the candidates the ranker saw, and which one a human
/// picked as the Best Shot.
public struct BestShotCalibrationCluster: Codable, Sendable, Equatable {
    public var clusterID: String
    /// Optional scene label, so calibration can be sliced by the categories
    /// that tend to stress the ranker differently (closed eyes on `people`,
    /// motion blur on `motion`, and so on). `nil` when the exporter did not
    /// categorize the cluster.
    public var category: BestShotCalibrationCategory?
    public var candidates: [BestShotCalibrationCandidate]
    /// `assetID` of the candidate a human labelled as the Best Shot.
    public var humanBestShotID: String

    public init(
        clusterID: String,
        category: BestShotCalibrationCategory? = nil,
        candidates: [BestShotCalibrationCandidate],
        humanBestShotID: String
    ) {
        self.clusterID = clusterID
        self.category = category
        self.candidates = candidates
        self.humanBestShotID = humanBestShotID
    }

    /// `BestShotRanker.decide` needs scores keyed by identifier; this is the
    /// one place that mapping is built so callers cannot key it inconsistently.
    public func scores(
        scoringModelVersion: Int,
        thumbnailConfigVersion: Int
    ) -> [String: PhotoQualityScore] {
        Dictionary(
            uniqueKeysWithValues: candidates.map {
                (
                    $0.assetID,
                    $0.qualityScore(
                        scoringModelVersion: scoringModelVersion,
                        thumbnailConfigVersion: thumbnailConfigVersion
                    )
                )
            }
        )
    }

    public var snapshots: [PhotoClusterAssetSnapshot] {
        candidates.map(\.snapshot)
    }
}

/// One candidate photo inside a labelled cluster: the same raw signals and
/// metadata `BestShotRanker` already ranks on, plus the identifiers needed to
/// rebuild the Core types it expects.
public struct BestShotCalibrationCandidate: Codable, Sendable, Equatable {
    /// Opaque, salted per export — never a PhotoKit `localIdentifier`. See the
    /// corpus doc comment for why.
    public var assetID: String
    public var signals: PhotoQualitySignals
    public var creationDate: Date?
    public var modificationDate: Date?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var isFavorite: Bool

    public init(
        assetID: String,
        signals: PhotoQualitySignals,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        pixelWidth: Int,
        pixelHeight: Int,
        isFavorite: Bool = false
    ) {
        self.assetID = assetID
        self.signals = signals
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isFavorite = isFavorite
    }

    /// The real Core snapshot type, so calibration exercises exactly what
    /// `BestShotRanker` sees in production rather than a parallel stand-in.
    public var snapshot: PhotoClusterAssetSnapshot {
        PhotoClusterAssetSnapshot(
            localIdentifier: assetID,
            creationDate: creationDate,
            modificationDate: modificationDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            isFavorite: isFavorite
        )
    }

    /// Wraps `signals` into the cache-row shape the ranker expects. Never
    /// Alike-enhanced: a labelled corpus captures the original photo, not an
    /// edit of it.
    public func qualityScore(
        scoringModelVersion: Int,
        thumbnailConfigVersion: Int
    ) -> PhotoQualityScore {
        PhotoQualityScore(
            localIdentifier: assetID,
            sourceModificationDate: modificationDate,
            scoringModelVersion: scoringModelVersion,
            thumbnailConfigVersion: thumbnailConfigVersion,
            signals: signals,
            isAlikeEnhanced: false
        )
    }
}

/// Scene categories a calibration cluster can be tagged with, matching the
/// situations Best Shot scoring treats differently (faces, motion, low light).
public enum BestShotCalibrationCategory: String, Codable, Sendable, CaseIterable {
    case people
    case kids
    case animals
    case night
    case motion
    case landscape
    case group
    case livePhoto
}
