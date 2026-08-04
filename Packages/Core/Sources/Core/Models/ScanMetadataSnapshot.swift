import Foundation

/// Baseline recorded when a scan finishes: when it completed plus the
/// fingerprint of the photo library at that moment.
///
/// `libraryChangeToken` is an opaque, archived PhotoKit persistent change
/// token. `imageAssetCount` is the coarse fallback used when that token can no
/// longer be resolved, so a missing token never means "assume the library
/// changed" — the previous behaviour, which prompted for a rescan immediately
/// after every successful scan.
public struct ScanMetadataSnapshot: Equatable, Sendable {
    public let lastScanDate: Date
    public let libraryChangeToken: Data?
    public let imageAssetCount: Int

    public init(
        lastScanDate: Date,
        libraryChangeToken: Data? = nil,
        imageAssetCount: Int = 0
    ) {
        self.lastScanDate = lastScanDate
        self.libraryChangeToken = libraryChangeToken
        self.imageAssetCount = max(0, imageAssetCount)
    }
}
