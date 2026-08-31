import Core
import Foundation
@preconcurrency import Photos

/// Quality analyzer that reads the cache first and only measures the misses.
///
/// This is what the app injects: decoding photos is the expensive part, and a
/// cluster reopened without changes must not pay for it twice.
public struct CachingPhotoQualityAnalyzer: PhotoQualityAnalyzing {
    private let repository: any PhotoQualityScoreRepository
    private let analyzer: any PhotoQualityAnalyzing
    private let config: PhotoQualityScoringConfig

    public init(
        repository: any PhotoQualityScoreRepository,
        config: PhotoQualityScoringConfig = .current
    ) {
        self.init(
            repository: repository,
            analyzer: PhotoQualityAnalysisService(config: config),
            config: config
        )
    }

    init(
        repository: any PhotoQualityScoreRepository,
        analyzer: any PhotoQualityAnalyzing,
        config: PhotoQualityScoringConfig = .current
    ) {
        self.repository = repository
        self.analyzer = analyzer
        self.config = config
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
            if let score = cached[asset.localIdentifier], score.isFresh(
                modificationDate: asset.modificationDate,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion
            ) {
                fresh[asset.localIdentifier] = score
            } else {
                misses.append(asset)
            }
        }

        guard !misses.isEmpty else {
            return identifiers.compactMap { fresh[$0] }
        }

        let measured = try await analyzer.scores(for: misses)
        if !measured.isEmpty {
            do {
                try await repository.saveScores(measured)
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
}
