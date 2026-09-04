import Foundation
import Photos

#if DEBUG

/// Mock implementation of PhotoQualityAnalyzing for previews and tests.
public actor MockPhotoQualityAnalyzer: PhotoQualityAnalyzing {
    public var scoresByIdentifier: [String: PhotoQualityScore] = [:]
    public var scoresError: Error?
    public var didCallScores = false
    public var requestedIdentifiers: [String] = []

    public init() {}

    public func setScores(_ scores: [PhotoQualityScore]) {
        scoresByIdentifier = Dictionary(uniqueKeysWithValues: scores.map { ($0.localIdentifier, $0) })
    }

    public func setScoresError(_ error: Error?) {
        scoresError = error
    }

    public func scores(for assets: [PHAsset]) async throws -> [PhotoQualityScore] {
        didCallScores = true
        let identifiers = assets.map(\.localIdentifier)
        requestedIdentifiers = identifiers
        if let scoresError { throw scoresError }
        return identifiers.compactMap { scoresByIdentifier[$0] }
    }
}

#endif
