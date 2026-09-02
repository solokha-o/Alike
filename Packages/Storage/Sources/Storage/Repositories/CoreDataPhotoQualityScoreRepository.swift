import CoreData
import Core
import Foundation

/// Core Data cache of Best Shot quality signals, stored on the photo rows the
/// cluster repository already maintains.
///
/// A row is a cache **miss** whenever the asset's `modificationDate`, the
/// scoring model version or the thumbnail config version differ from what was
/// stored — that is the whole invalidation rule.
public final class CoreDataPhotoQualityScoreRepository: PhotoQualityScoreRepository {
    private enum Constants {
        static let maxInPredicateBatchSize = 500
    }

    private let persistence: PersistenceController

    public init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    public func loadScores(localIdentifiers: [String]) async throws -> [String: PhotoQualityScore] {
        guard !localIdentifiers.isEmpty else { return [:] }

        return try await persistence.performBackgroundTask { context in
            let decoder = JSONDecoder()
            var scores: [String: PhotoQualityScore] = [:]

            for batch in Array(Set(localIdentifiers)).chunked(into: Constants.maxInPredicateBatchSize) {
                let request = PhotoEntity.fetchRequest()
                request.predicate = NSPredicate(format: "localIdentifier IN %@", batch)
                for photo in try context.fetch(request) {
                    guard let data = photo.qualitySignalsData,
                          let signals = try? decoder.decode(PhotoQualitySignals.self, from: data) else {
                        continue
                    }
                    scores[photo.localIdentifier] = PhotoQualityScore(
                        localIdentifier: photo.localIdentifier,
                        sourceModificationDate: photo.qualitySourceModificationDate,
                        scoringModelVersion: Int(photo.scoringModelVersion),
                        thumbnailConfigVersion: Int(photo.thumbnailConfigVersion),
                        signals: signals,
                        scoredAt: photo.qualityScoredAt ?? Date(timeIntervalSince1970: 0),
                        isAlikeEnhanced: photo.isAlikeEnhanced
                    )
                }
            }

            return scores
        }
    }

    public func saveScores(_ scores: [PhotoQualityScore]) async throws {
        guard !scores.isEmpty else { return }

        try await persistence.performBackgroundTask { context in
            context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
            let encoder = JSONEncoder()
            let scoresByIdentifier = Dictionary(
                scores.map { ($0.localIdentifier, $0) },
                uniquingKeysWith: { _, latest in latest }
            )

            var existing: [String: PhotoEntity] = [:]
            for batch in Array(scoresByIdentifier.keys).chunked(into: Constants.maxInPredicateBatchSize) {
                let request = PhotoEntity.fetchRequest()
                request.predicate = NSPredicate(format: "localIdentifier IN %@", batch)
                for photo in try context.fetch(request) {
                    existing[photo.localIdentifier] = photo
                }
            }

            for (localIdentifier, score) in scoresByIdentifier {
                // A photo can be scored before it lands in a stored cluster, so
                // the row is created on demand rather than dropping the score.
                let photo = existing[localIdentifier] ?? {
                    let created = PhotoEntity(context: context)
                    created.localIdentifier = localIdentifier
                    return created
                }()
                photo.qualitySignalsData = try encoder.encode(score.signals)
                photo.qualitySourceModificationDate = score.sourceModificationDate
                photo.scoringModelVersion = Int32(clamping: score.scoringModelVersion)
                photo.thumbnailConfigVersion = Int32(clamping: score.thumbnailConfigVersion)
                photo.qualityScoredAt = score.scoredAt
                photo.isAlikeEnhanced = score.isAlikeEnhanced
            }

            try context.save()
        }
    }

    public func deleteAllScores() async throws {
        try await persistence.performBackgroundTask { context in
            let request = PhotoEntity.fetchRequest()
            request.predicate = NSPredicate(format: "qualitySignalsData != nil")
            for photo in try context.fetch(request) {
                // A row this repository created for a photo that never made it
                // into a stored cluster has nothing left once its score is
                // gone, and no other cleanup path would ever remove it.
                if photo.cluster == nil {
                    context.delete(photo)
                    continue
                }
                photo.qualitySignalsData = nil
                photo.qualitySourceModificationDate = nil
                photo.scoringModelVersion = 0
                photo.thumbnailConfigVersion = 0
                photo.qualityScoredAt = nil
                photo.isAlikeEnhanced = false
            }
            try context.save()
        }
    }
}
