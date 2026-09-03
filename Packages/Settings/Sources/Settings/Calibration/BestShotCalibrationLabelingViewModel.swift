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

/// Drives the DEBUG-only Best Shot labelling screen: walks real clusters one
/// at a time, scores them through the same cache-first analyzer production
/// uses, and accumulates human labels into a corpus that can be exported and
/// resumed across relaunches without ever persisting PhotoKit identity.
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

    public private(set) var currentCluster: PhotoCluster?
    /// `internal`, not `private`: the view drives selection off it, and tests
    /// seed it directly to exercise labelling without a real `PHAsset`.
    private(set) var currentPreparedCluster: BestShotCalibrationPreparedCluster?
    public private(set) var isLoadingCluster = false
    public private(set) var isScoring = false
    public private(set) var loadErrorMessage: String?
    /// `true` once a `loadNextCluster()` found no unlabelled cluster left.
    public private(set) var isFinished = false

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
        } else {
            self.salt = UUID().uuidString
            self.labelledClusters = []
        }
    }

    public var labelledCount: Int {
        labelledClusters.count
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
        guard let prepared = currentPreparedCluster, prepared.clusterID == clusterID else { return }
        guard prepared.candidates.contains(where: { $0.localIdentifier == bestShotAssetID }) else { return }

        let candidates = prepared.candidates.map { candidate in
            BestShotCalibrationCandidate(
                assetID: anonymizedAssetID(for: candidate.localIdentifier),
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
        persistSession()
        currentCluster = nil
        currentPreparedCluster = nil
    }

    /// A `BestShotCalibrationCorpus` covering every label recorded so far,
    /// with the schema's current versions. Never carries the session salt or
    /// any PhotoKit `localIdentifier`.
    public func exportJSON() throws -> Data {
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
        labelledClusters.removeAll()
        salt = UUID().uuidString
        currentCluster = nil
        currentPreparedCluster = nil
        isFinished = false
        defaults.removeObject(forKey: PreferenceKey.session)
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
}

private extension BestShotCalibrationLabelingViewModel {
    struct PersistedSession: Codable {
        var salt: String
        var labelledClusters: [BestShotCalibrationCluster]
    }

    func anonymizedAssetID(for localIdentifier: String) -> String {
        let digest = SHA256.hash(data: Data((localIdentifier + salt).utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    func persistSession() {
        let session = PersistedSession(salt: salt, labelledClusters: labelledClusters)
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
