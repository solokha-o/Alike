#if DEBUG
import Core
import CryptoKit
import Foundation
import Photos
import PhotoAnalysis
import Storage

/// One candidate as measured for the cluster currently on screen. Keeps the
/// real PhotoKit `localIdentifier` in memory only — it is what the grid uses
/// to fetch the thumbnail — and is never itself written to the exported file.
struct BestShotCalibrationPreparedCandidate: Sendable, Equatable {
    let localIdentifier: String
    let signals: PhotoQualitySignals
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let isFavorite: Bool
}

/// The cluster currently being labelled, already scored.
struct BestShotCalibrationPreparedCluster: Sendable, Equatable {
    let clusterID: UUID
    let candidates: [BestShotCalibrationPreparedCandidate]
}

/// The outcome of `remeasureCorpus()`: how many labelled clusters were
/// re-scored successfully versus dropped because their photos could no
/// longer be resolved (deleted from the library since labelling).
public struct BestShotCalibrationRemeasureResult: Sendable, Equatable {
    public let remeasuredCount: Int
    public let droppedCount: Int
}

/// Thrown by `exportJSON()` (and therefore `exportedCorpusFileURL()`) when the
/// corpus is not safe to export as-is.
public enum BestShotCalibrationExportError: Error, Equatable {
    /// At least one labelled cluster's signals were measured under an older
    /// `thumbnailConfigVersion` than the one `exportJSON()` is about to stamp
    /// the whole corpus with. Exporting anyway would let `CorpusLoader` trust
    /// stale signals as current — run `remeasureCorpus()` first.
    case staleMeasurements(count: Int)
}

extension BestShotCalibrationExportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .staleMeasurements(count):
            let clusterWord = count == 1 ? "cluster" : "clusters"
            return "\(count) labelled \(clusterWord) still hold signals measured under an older "
                + "thumbnail geometry. Re-measure the corpus before exporting so every stamped "
                + "version matches what was actually measured."
        }
    }
}

/// Drives the DEBUG-only Best Shot labelling screen: walks real clusters one
/// at a time, scores them through the same cache-first analyzer production
/// uses, and accumulates human labels into a corpus that can be exported and
/// resumed across relaunches without ever persisting PhotoKit identity.
///
/// WHY the resume buffer also keeps real `localIdentifier`s (never exported,
/// see `PersistedSession` below): raw `PhotoQualitySignals` are only
/// comparable to the analysis pipeline that produced them. A geometry change
/// to the pipeline (e.g. the face-detection size gate) bumps
/// `thumbnailConfigVersion` and makes every already-collected corpus's
/// signals stale, even though the human's "which photo is best" label is
/// still valid. Re-measuring needs the real photo back, and the exported
/// corpus only ever carries anonymized `assetID`s — so the on-device DEBUG
/// buffer keeps the mapping the export deliberately discards.
@MainActor
@Observable
public final class BestShotCalibrationLabelingViewModel {
    /// Namespaced separately from `Core`'s `AppPreferenceKey` — this key never
    /// belongs to a shipping build, so it does not live in the shared registry.
    private enum PreferenceKey {
        static let session = "debug.bestShotCalibration.session.v1"
    }

    private let clusterRepository: any PhotoClusterRepository
    private let qualityAnalyzer: any PhotoQualityAnalyzing
    private let defaults: UserDefaults

    /// Per-session salt anonymized asset IDs are derived from. Regenerated on
    /// `reset()`, otherwise stable for the life of this labelling session so
    /// the same photo always anonymizes to the same ID within one export.
    private var salt: String
    private var labelledClusters: [BestShotCalibrationCluster]
    /// DEBUG-only, resume-buffer-only: real PhotoKit `localIdentifier`s for
    /// every candidate in a labelled cluster, keyed by the cluster's
    /// `clusterID` and then by the candidate's anonymized `assetID`. This is
    /// what lets `remeasureCorpus()` find the photos again; it is never
    /// written into `exportJSON()`'s output.
    private var candidateLocalIdentifiers: [String: [String: String]]
    /// `thumbnailConfigVersion` in effect the last time each cluster's
    /// signals were actually measured (labelled, or re-measured). Lets the
    /// UI tell a fresh corpus from one that predates a geometry change,
    /// without changing the exported schema to carry it.
    private var measuredThumbnailConfigVersions: [String: Int]

    public private(set) var currentCluster: PhotoCluster?
    /// `internal`, not `private`: the view drives selection off it, and tests
    /// seed it directly to exercise labelling without a real `PHAsset`.
    private(set) var currentPreparedCluster: BestShotCalibrationPreparedCluster?
    public private(set) var isLoadingCluster = false
    public private(set) var isScoring = false
    public private(set) var loadErrorMessage: String?
    /// `true` once a `loadNextCluster()` found no unlabelled cluster left.
    public private(set) var isFinished = false
    public private(set) var isRemeasuring = false
    /// `(completed, total)` clusters processed so far in an in-flight
    /// `remeasureCorpus()`, for a determinate progress indicator.
    public private(set) var remeasureProgress: (completed: Int, total: Int) = (0, 0)
    /// Test seam only, see `remeasureCorpus()`. `nil` (a no-op) in production.
    var remeasureStepHookForTesting: (@Sendable () async -> Void)?

    public init(
        clusterRepository: (any PhotoClusterRepository)? = nil,
        qualityAnalyzer: (any PhotoQualityAnalyzing)? = nil,
        defaults: UserDefaults = .standard
    ) {
        let clusterRepository = clusterRepository ?? CoreDataPhotoClusterRepository()
        let qualityAnalyzer = qualityAnalyzer
            ?? CachingPhotoQualityAnalyzer(repository: CoreDataPhotoQualityScoreRepository())
        self.clusterRepository = clusterRepository
        self.qualityAnalyzer = qualityAnalyzer
        self.defaults = defaults

        if let session = Self.loadPersistedSession(defaults: defaults) {
            self.salt = session.salt
            self.labelledClusters = session.labelledClusters
            self.candidateLocalIdentifiers = session.candidateLocalIdentifiers
            self.measuredThumbnailConfigVersions = session.measuredThumbnailConfigVersions
        } else {
            self.salt = UUID().uuidString
            self.labelledClusters = []
            self.candidateLocalIdentifiers = [:]
            self.measuredThumbnailConfigVersions = [:]
        }
    }

    public var labelledCount: Int {
        labelledClusters.count
    }

    /// `thumbnailConfigVersion` production would stamp on a score measured
    /// right now — the number to compare the corpus's own vintage against.
    public var currentThumbnailConfigVersion: Int {
        PhotoQualityScoringConfig.current.thumbnailConfigVersion
    }

    /// How many labelled clusters were last measured under a different
    /// `thumbnailConfigVersion` than the current one (including clusters
    /// from before this tracking existed, which count as unknown/stale).
    /// Zero and non-empty means the corpus is current; a `Re-measure corpus`
    /// pass is not needed.
    public var clustersNeedingRemeasureCount: Int {
        let current = currentThumbnailConfigVersion
        return labelledClusters.filter { measuredThumbnailConfigVersions[$0.clusterID] != current }.count
    }

    /// Candidate local identifiers of the cluster on screen, in cluster order,
    /// for the grid to lay out and fetch thumbnails for.
    public var currentCandidateIdentifiers: [String] {
        currentPreparedCluster?.candidates.map(\.localIdentifier) ?? []
    }

    /// Live `PHAsset`s for the cluster on screen, in the same order as
    /// `currentCandidateIdentifiers`, for the grid to request thumbnails from.
    public var currentCandidateAssets: [PHAsset] {
        guard let cluster = currentCluster else { return [] }
        let assetsByIdentifier = Dictionary(
            cluster.assets.map { ($0.localIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return currentCandidateIdentifiers.compactMap { assetsByIdentifier[$0] }
    }

    /// Loads clusters from the repository and advances `currentCluster` to the
    /// first one with more than one photo that has not been labelled yet,
    /// scoring it as it becomes current.
    public func loadNextCluster() async {
        isLoadingCluster = true
        loadErrorMessage = nil
        defer { isLoadingCluster = false }

        do {
            let clusters = try await clusterRepository.loadClusters()
            let labelledIDs = Set(labelledClusters.map(\.clusterID))
            guard let next = clusters.first(where: {
                $0.assets.count > 1 && !labelledIDs.contains($0.id.uuidString)
            }) else {
                currentCluster = nil
                currentPreparedCluster = nil
                isFinished = true
                return
            }
            isFinished = false
            currentCluster = next
            await scoreIfNeeded(for: next)
        } catch {
            AppLog.ui.error(
                "\(AppLog.tag(.error, "Failed to load clusters for calibration labelling: \(error.localizedDescription)"))"
            )
            loadErrorMessage = error.localizedDescription
        }
    }

    /// Scores `cluster`'s assets through the same cache-first analyzer
    /// production uses, so a photo already scored during normal app use is
    /// never re-decoded here. A no-op once `cluster` is already prepared.
    public func scoreIfNeeded(for cluster: PhotoCluster) async {
        guard currentPreparedCluster?.clusterID != cluster.id else { return }
        isScoring = true
        defer { isScoring = false }

        do {
            let scores = try await qualityAnalyzer.scores(for: cluster.assets)
            let scoresByIdentifier = Dictionary(
                scores.map { ($0.localIdentifier, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            let candidates = cluster.assets.compactMap { asset -> BestShotCalibrationPreparedCandidate? in
                guard let score = scoresByIdentifier[asset.localIdentifier] else { return nil }
                return BestShotCalibrationPreparedCandidate(
                    localIdentifier: asset.localIdentifier,
                    signals: score.signals,
                    creationDate: asset.creationDate,
                    modificationDate: asset.modificationDate,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    isFavorite: asset.isFavorite
                )
            }
            guard currentCluster?.id == cluster.id else { return }
            currentPreparedCluster = BestShotCalibrationPreparedCluster(
                clusterID: cluster.id,
                candidates: candidates
            )
        } catch {
            AppLog.ui.error(
                "\(AppLog.tag(.error, "Failed to score cluster for calibration labelling: \(error.localizedDescription)"))"
            )
        }
    }

    /// Records the human's pick for the currently prepared cluster, appending
    /// an anonymized entry to the in-memory corpus and persisting it, then
    /// clears the current cluster so the caller can load the next one.
    public func recordLabel(
        clusterID: UUID,
        bestShotAssetID: String,
        category: BestShotCalibrationCategory?
    ) {
        // `remeasureCorpus()` suspends once per cluster and rebuilds
        // `labelledClusters` wholesale from what it started with when it
        // resumes; a label recorded during one of those suspensions would be
        // silently overwritten by that rebuild. Reject it instead of losing
        // it quietly.
        guard !isRemeasuring else { return }
        guard let prepared = currentPreparedCluster, prepared.clusterID == clusterID else { return }
        guard prepared.candidates.contains(where: { $0.localIdentifier == bestShotAssetID }) else { return }

        var localIdentifiersByAssetID: [String: String] = [:]
        let candidates = prepared.candidates.map { candidate -> BestShotCalibrationCandidate in
            let assetID = anonymizedAssetID(for: candidate.localIdentifier)
            localIdentifiersByAssetID[assetID] = candidate.localIdentifier
            return BestShotCalibrationCandidate(
                assetID: assetID,
                signals: candidate.signals,
                creationDate: candidate.creationDate,
                modificationDate: candidate.modificationDate,
                pixelWidth: candidate.pixelWidth,
                pixelHeight: candidate.pixelHeight,
                isFavorite: candidate.isFavorite
            )
        }
        let entry = BestShotCalibrationCluster(
            clusterID: clusterID.uuidString,
            category: category,
            candidates: candidates,
            humanBestShotID: anonymizedAssetID(for: bestShotAssetID)
        )

        labelledClusters.append(entry)
        candidateLocalIdentifiers[entry.clusterID] = localIdentifiersByAssetID
        measuredThumbnailConfigVersions[entry.clusterID] = currentThumbnailConfigVersion
        persistSession()
        currentCluster = nil
        currentPreparedCluster = nil
    }

    /// A `BestShotCalibrationCorpus` covering every label recorded so far,
    /// with the schema's current versions. Never carries the session salt or
    /// any PhotoKit `localIdentifier`.
    ///
    /// Throws `BestShotCalibrationExportError.staleMeasurements` when
    /// `clustersNeedingRemeasureCount > 0`: stamping the whole corpus with the
    /// current `thumbnailConfigVersion` while some entries' signals were
    /// actually measured under an older one would make `CorpusLoader` trust
    /// stale signals as current. Run `remeasureCorpus()` first.
    public func exportJSON() throws -> Data {
        let staleCount = clustersNeedingRemeasureCount
        guard staleCount == 0 else {
            throw BestShotCalibrationExportError.staleMeasurements(count: staleCount)
        }
        let corpus = BestShotCalibrationCorpus(
            exportedAt: Date(),
            scoringModelVersion: PhotoQualityScoringConfig.current.scoringModelVersion,
            thumbnailConfigVersion: PhotoQualityScoringConfig.current.thumbnailConfigVersion,
            entries: labelledClusters
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(corpus)
    }

    /// Writes `exportJSON()` to a temp file so `ShareLink` can hand it off.
    public func exportedCorpusFileURL() throws -> URL {
        let data = try exportJSON()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alike-best-shot-calibration-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Clears every recorded label and starts a fresh anonymization salt, so a
    /// discarded corpus cannot be stitched back together with a later one.
    public func reset() {
        // Same reasoning as the guard in `recordLabel`: a reset mid-remeasure
        // would be clobbered by the in-flight rebuild's final assignment.
        guard !isRemeasuring else { return }
        labelledClusters.removeAll()
        candidateLocalIdentifiers.removeAll()
        measuredThumbnailConfigVersions.removeAll()
        salt = UUID().uuidString
        currentCluster = nil
        currentPreparedCluster = nil
        isFinished = false
        defaults.removeObject(forKey: PreferenceKey.session)
    }

    /// Re-runs every labelled cluster through the same `PhotoQualityAnalyzing`
    /// this screen already scores with, replacing each candidate's signals
    /// with a fresh measurement while keeping `clusterID`, `category` and
    /// `humanBestShotID` — and the same anonymized `assetID`s, since the same
    /// `localIdentifier` re-hashed with the persisted salt reproduces them —
    /// exactly as they were. The human label survives; only the signals move.
    ///
    /// This deliberately goes through `qualityAnalyzer.scores(for:)` rather
    /// than reading anything cached: once `thumbnailConfigVersion` has been
    /// bumped, `PhotoQualityScore.isFresh` already makes the cache a miss for
    /// these assets, so the normal analyzer path re-measures on its own — but
    /// nothing here special-cases version, and nothing here should ever be
    /// changed to shortcut through a cached row.
    ///
    /// A cluster whose photo can no longer be resolved (deleted from the
    /// library since labelling, or `qualityAnalyzer` fails on it) is dropped
    /// from the corpus rather than exported with stale signals; the returned
    /// result reports how many that was.
    @discardableResult
    public func remeasureCorpus() async -> BestShotCalibrationRemeasureResult {
        isRemeasuring = true
        remeasureProgress = (0, labelledClusters.count)
        defer {
            isRemeasuring = false
            remeasureProgress = (0, 0)
        }

        var rebuiltClusters: [BestShotCalibrationCluster] = []
        var rebuiltLocalIdentifiers: [String: [String: String]] = [:]
        var rebuiltVersions: [String: Int] = [:]
        var droppedCount = 0

        for cluster in labelledClusters {
            defer { remeasureProgress.completed += 1 }

            // Test seam only: `nil` in production, so this never adds a
            // suspension point beyond the real ones below. Lets a test hold
            // this loop open at a genuine `await` to exercise what happens
            // when `recordLabel`/`reset` are called while `isRemeasuring` is
            // true — see `remeasureStepHookForTesting`.
            if let hook = remeasureStepHookForTesting { await hook() }

            if let fresh = await remeasuredCluster(cluster) {
                rebuiltClusters.append(fresh)
                rebuiltLocalIdentifiers[cluster.clusterID] = candidateLocalIdentifiers[cluster.clusterID]
                rebuiltVersions[cluster.clusterID] = currentThumbnailConfigVersion
            } else {
                droppedCount += 1
            }
        }

        labelledClusters = rebuiltClusters
        candidateLocalIdentifiers = rebuiltLocalIdentifiers
        measuredThumbnailConfigVersions = rebuiltVersions
        persistSession()

        return BestShotCalibrationRemeasureResult(
            remeasuredCount: rebuiltClusters.count,
            droppedCount: droppedCount
        )
    }
}

extension BestShotCalibrationLabelingViewModel {
    /// Test seam: lets tests exercise `recordLabel`/`exportJSON` against a
    /// hand-built cluster without constructing a real `PHAsset`, which
    /// PhotoKit does not allow outside the library.
    func setPreparedClusterForTesting(_ cluster: BestShotCalibrationPreparedCluster) {
        currentCluster = PhotoCluster(id: cluster.clusterID, assets: [])
        currentPreparedCluster = cluster
    }

    /// Test seam: the `localIdentifier` map recorded for one labelled
    /// cluster's resume buffer, so a test can assert it round-trips through
    /// `PersistedSession` without reaching into `UserDefaults` itself.
    func candidateLocalIdentifiersForTesting(clusterID: String) -> [String: String]? {
        candidateLocalIdentifiers[clusterID]
    }

    /// Test seam: exposes the same salted hash `recordLabel` uses, so a test
    /// can confirm that re-hashing a stored `localIdentifier` reproduces the
    /// candidate's anonymized `assetID` — the property `remeasureCorpus()`
    /// relies on to keep an `assetID` stable across a re-measure.
    func anonymizedAssetIDForTesting(_ localIdentifier: String) -> String {
        anonymizedAssetID(for: localIdentifier)
    }

    /// Test seam: overrides the recorded "last measured under this
    /// `thumbnailConfigVersion`" value for one already-labelled cluster, so a
    /// test can simulate a geometry change having happened since labelling
    /// (`clustersNeedingRemeasureCount` > 0) without needing a real analyzer
    /// re-run or a way to mutate `PhotoQualityScoringConfig.current`.
    func setMeasuredThumbnailConfigVersionForTesting(clusterID: String, version: Int) {
        measuredThumbnailConfigVersions[clusterID] = version
    }
}

private extension BestShotCalibrationLabelingViewModel {
    /// The DEBUG resume buffer, persisted in `UserDefaults`. Everything past
    /// `labelledClusters` here is strictly on-device bookkeeping —
    /// `candidateLocalIdentifiers` in particular must never appear in
    /// `exportJSON()`'s output; see the class doc comment for why it exists.
    /// `candidateLocalIdentifiers` and `measuredThumbnailConfigVersions`
    /// default to empty on decode so a session persisted before this field
    /// existed still loads.
    struct PersistedSession: Codable {
        var salt: String
        var labelledClusters: [BestShotCalibrationCluster]
        var candidateLocalIdentifiers: [String: [String: String]]
        var measuredThumbnailConfigVersions: [String: Int]

        private enum CodingKeys: String, CodingKey {
            case salt, labelledClusters, candidateLocalIdentifiers, measuredThumbnailConfigVersions
        }

        init(
            salt: String,
            labelledClusters: [BestShotCalibrationCluster],
            candidateLocalIdentifiers: [String: [String: String]],
            measuredThumbnailConfigVersions: [String: Int]
        ) {
            self.salt = salt
            self.labelledClusters = labelledClusters
            self.candidateLocalIdentifiers = candidateLocalIdentifiers
            self.measuredThumbnailConfigVersions = measuredThumbnailConfigVersions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            salt = try container.decode(String.self, forKey: .salt)
            labelledClusters = try container.decode([BestShotCalibrationCluster].self, forKey: .labelledClusters)
            candidateLocalIdentifiers = try container.decodeIfPresent(
                [String: [String: String]].self,
                forKey: .candidateLocalIdentifiers
            ) ?? [:]
            measuredThumbnailConfigVersions = try container.decodeIfPresent(
                [String: Int].self,
                forKey: .measuredThumbnailConfigVersions
            ) ?? [:]
        }
    }

    func anonymizedAssetID(for localIdentifier: String) -> String {
        let digest = SHA256.hash(data: Data((localIdentifier + salt).utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    /// Re-measures one cluster: resolves its stored `localIdentifier`s back
    /// to `PHAsset`s, re-scores them, and rebuilds the cluster with fresh
    /// signals — or returns `nil` if any candidate can no longer be
    /// resolved or re-scored, signalling the caller to drop it.
    func remeasuredCluster(_ cluster: BestShotCalibrationCluster) async -> BestShotCalibrationCluster? {
        guard let localIdentifiersByAssetID = candidateLocalIdentifiers[cluster.clusterID] else { return nil }
        let orderedLocalIdentifiers = cluster.candidates.map(\.assetID).compactMap {
            localIdentifiersByAssetID[$0]
        }
        guard orderedLocalIdentifiers.count == cluster.candidates.count else { return nil }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: orderedLocalIdentifiers, options: nil)
        var assetsByLocalIdentifier: [String: PHAsset] = [:]
        fetchResult.enumerateObjects { asset, _, _ in
            assetsByLocalIdentifier[asset.localIdentifier] = asset
        }
        guard assetsByLocalIdentifier.count == orderedLocalIdentifiers.count else { return nil }

        do {
            let orderedAssets = orderedLocalIdentifiers.compactMap { assetsByLocalIdentifier[$0] }
            let scores = try await qualityAnalyzer.scores(for: orderedAssets)
            let scoresByLocalIdentifier = Dictionary(
                scores.map { ($0.localIdentifier, $0) },
                uniquingKeysWith: { _, latest in latest }
            )

            var freshCandidates: [BestShotCalibrationCandidate] = []
            freshCandidates.reserveCapacity(cluster.candidates.count)
            for candidate in cluster.candidates {
                guard let localIdentifier = localIdentifiersByAssetID[candidate.assetID],
                      let asset = assetsByLocalIdentifier[localIdentifier],
                      let score = scoresByLocalIdentifier[localIdentifier]
                else { return nil }
                freshCandidates.append(
                    BestShotCalibrationCandidate(
                        assetID: candidate.assetID,
                        signals: score.signals,
                        creationDate: asset.creationDate,
                        modificationDate: asset.modificationDate,
                        pixelWidth: asset.pixelWidth,
                        pixelHeight: asset.pixelHeight,
                        isFavorite: asset.isFavorite
                    )
                )
            }

            return BestShotCalibrationCluster(
                clusterID: cluster.clusterID,
                category: cluster.category,
                candidates: freshCandidates,
                humanBestShotID: cluster.humanBestShotID
            )
        } catch {
            AppLog.ui.error(
                "\(AppLog.tag(.error, "Failed to remeasure calibration cluster \(cluster.clusterID): \(error.localizedDescription)"))"
            )
            return nil
        }
    }

    func persistSession() {
        let session = PersistedSession(
            salt: salt,
            labelledClusters: labelledClusters,
            candidateLocalIdentifiers: candidateLocalIdentifiers,
            measuredThumbnailConfigVersions: measuredThumbnailConfigVersions
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { return }
        defaults.set(data, forKey: PreferenceKey.session)
    }

    static func loadPersistedSession(defaults: UserDefaults) -> PersistedSession? {
        guard let data = defaults.data(forKey: PreferenceKey.session) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistedSession.self, from: data)
    }
}
#endif
