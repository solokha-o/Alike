import Core
import Foundation
@preconcurrency import Photos

/// Quality analyzer that reads the cache first and only measures the misses.
///
/// This is what the app injects: decoding photos is the expensive part, and a
/// cluster reopened without changes must not pay for it twice.
public struct CachingPhotoQualityAnalyzer: PhotoQualityAnalyzing {
    /// Answers what edit is on an asset right now. Only the rows the cache
    /// serves pre-enhancement signals for ever ask.
    typealias EnhancementAvailabilityProvider = @Sendable (String) async -> PhotoEnhancementAvailability

    private let repository: any PhotoQualityScoreRepository
    private let analyzer: any PhotoQualityAnalyzing
    private let config: PhotoQualityScoringConfig
    private let enhancementAvailability: EnhancementAvailabilityProvider?

    public init(
        repository: any PhotoQualityScoreRepository,
        config: PhotoQualityScoringConfig = .current
    ) {
        let enhancementService = PhotoKitEnhancementService(
            qualityScoreRepository: repository,
            config: config
        )
        self.init(
            repository: repository,
            analyzer: PhotoQualityAnalysisService(config: config),
            config: config,
            enhancementAvailability: { await enhancementService.availability(localIdentifier: $0) }
        )
    }

    init(
        repository: any PhotoQualityScoreRepository,
        analyzer: any PhotoQualityAnalyzing,
        config: PhotoQualityScoringConfig = .current,
        enhancementAvailability: EnhancementAvailabilityProvider? = nil
    ) {
        self.repository = repository
        self.analyzer = analyzer
        self.config = config
        self.enhancementAvailability = enhancementAvailability
    }

    public func scores(for assets: [PHAsset]) async throws -> [PhotoQualityScore] {
        guard !assets.isEmpty else { return [] }

        let identifiers = assets.map(\.localIdentifier)
        var cached: [String: PhotoQualityScore]
        do {
            cached = try await repository.loadScores(localIdentifiers: identifiers)
        } catch {
            // A broken cache is a slow path, not a failure: measure everything.
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to load cached quality scores: \(error.localizedDescription)"))"
            )
            cached = [:]
        }

        var fresh: [String: PhotoQualityScore] = [:]
        var misses: [PHAsset] = []
        for asset in assets {
            guard let score = cached[asset.localIdentifier], score.isFresh(
                modificationDate: asset.modificationDate,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion
            ) else {
                misses.append(asset)
                continue
            }
            if score.isAlikeEnhanced, await hasLostOurEdit(asset.localIdentifier) {
                misses.append(asset)
                continue
            }
            fresh[asset.localIdentifier] = score
        }

        guard !misses.isEmpty else {
            return identifiers.compactMap { fresh[$0] }
        }

        let measured = try await analyzer.scores(for: misses)
        // A failure is a moment, not a measurement: an asset that was offline,
        // still downloading, or timed out must be retried next time rather than
        // cached as a fresh "unknown" forever.
        let usableScores = measured.filter { $0.signals.isUsable }
        if !usableScores.isEmpty {
            do {
                try await repository.saveScores(usableScores)
            } catch {
                AppLog.storage.error(
                    "\(AppLog.tag(.error, "Failed to cache quality scores: \(error.localizedDescription)"))"
                )
            }
        }

        for score in measured {
            fresh[score.localIdentifier] = score
        }
        return identifiers.compactMap { fresh[$0] }
    }

    /// `PhotoQualityScore.isFresh` keeps an Alike-enhanced row for good, because
    /// its signals are the only surviving measurement of the original. That
    /// holds only for as long as our edit is the edit on the photo: once the
    /// user edits it in another app, or reverts it in Photos, those signals
    /// describe pixels nobody will see again and the ranker has to measure what
    /// is actually there.
    private func hasLostOurEdit(_ localIdentifier: String) async -> Bool {
        guard let enhancementAvailability else { return false }
        switch await enhancementAvailability(localIdentifier) {
        case .available, .editedElsewhere:
            // Asking also clears the stale marker in the cache, so this costs
            // one resolve per photo that changed, not one per ranking.
            return true
        case .enhanced, .unavailable:
            // `.unavailable` is "cannot tell", not "the edit is gone": an
            // unreadable or non-editable asset is no reason to throw away the
            // only measurement of the original that exists.
            return false
        }
    }
}
