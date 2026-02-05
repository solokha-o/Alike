import Foundation

/// Cached Vision feature print for a photo asset, stored by local identifier.
public struct PhotoFeaturePrintCacheEntry: Sendable {
    public let localIdentifier: String
    public let modificationDate: Date?
    public let featurePrintData: Data

    public init(
        localIdentifier: String,
        modificationDate: Date?,
        featurePrintData: Data
    ) {
        self.localIdentifier = localIdentifier
        self.modificationDate = modificationDate
        self.featurePrintData = featurePrintData
    }
}

/// Repository for persisting and reusing Vision feature prints across scans.
public protocol PhotoFeaturePrintRepository: Sendable {
    /// Loads cached feature prints keyed by `PHAsset.localIdentifier`.
    func loadFeaturePrints(for localIdentifiers: [String]) async throws -> [String: PhotoFeaturePrintCacheEntry]

    /// Inserts or updates cached feature prints.
    func upsertFeaturePrints(_ entries: [PhotoFeaturePrintCacheEntry]) async throws
}

