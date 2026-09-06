import Foundation

#if DEBUG

/// Mock implementation of PhotoQualityScoreRepository for previews and tests.
public actor MockPhotoQualityScoreRepository: PhotoQualityScoreRepository {
    public var storedScores: [String: PhotoQualityScore] = [:]
    public var loadScoresError: Error?
    public var saveScoresError: Error?
    public var deleteAllScoresError: Error?

    public var didCallLoadScores = false
    public var didCallSaveScores = false
    public var didCallDeleteAllScores = false

    public init() {}

    public func setStoredScores(_ scores: [PhotoQualityScore]) {
        storedScores = Dictionary(uniqueKeysWithValues: scores.map { ($0.localIdentifier, $0) })
    }

    public func setLoadScoresError(_ error: Error?) {
        loadScoresError = error
    }

    public func loadScores(localIdentifiers: [String]) async throws -> [String: PhotoQualityScore] {
        didCallLoadScores = true
        if let loadScoresError { throw loadScoresError }
        return storedScores.filter { localIdentifiers.contains($0.key) }
    }

    public func saveScores(_ scores: [PhotoQualityScore]) async throws {
        didCallSaveScores = true
        if let saveScoresError { throw saveScoresError }
        for score in scores {
            storedScores[score.localIdentifier] = score
        }
    }

    public func deleteAllScores() async throws {
        didCallDeleteAllScores = true
        if let deleteAllScoresError { throw deleteAllScoresError }
        storedScores.removeAll()
    }
}

#endif
