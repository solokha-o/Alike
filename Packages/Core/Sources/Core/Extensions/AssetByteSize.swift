import Foundation
import os
import Photos

/// The single source of «bytes per asset» for every cleanup and reclaimable figure.
///
/// Bytes are the sum of the asset's resource file sizes — original, edits and a
/// paired Live Photo video — which is what deleting the asset frees. When PhotoKit
/// reports no readable size, the pixel heuristic stands in so a figure is never 0.
///
/// Resource lookups are not free on a large library, so results are cached in
/// memory per `localIdentifier` and dropped when the asset's `modificationDate`
/// moves. Warm the cache off the main actor with ``prewarm(_:)``.
public enum AssetByteSize {
    /// Unit of persisted byte sums. `nil` in a stored payload means the legacy
    /// pixel heuristic; `1` means resource file sizes.
    public static let currentVersion = 1

    private struct CacheEntry {
        let modificationDate: Date?
        let bytes: Int64
    }

    private struct CacheState {
        var entries: [String: CacheEntry] = [:]
        /// Bumped whenever a size is measured, not when one is seeded, so a caller
        /// can tell whether the persisted copy is behind.
        var generation = 0
    }

    private static let photosBundle = Bundle(for: PHAsset.self)
    private static let fileSizeSelector = NSSelectorFromString("fileSize")
    private static let cache = OSAllocatedUnfairLock(initialState: CacheState())

    public static func bytes(for asset: PHAsset) -> Int64 {
        // A PHAsset subclass defined outside Photos (a test double) has no library
        // object behind it: it always gets the heuristic and never touches the cache.
        guard Bundle(for: type(of: asset)) == photosBundle else {
            return heuristicBytes(pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight)
        }
        let identifier = asset.localIdentifier
        let modificationDate = asset.modificationDate
        if let cached = cache.withLock({ $0.entries[identifier] }),
           isSameModificationDate(cached.modificationDate, modificationDate) {
            return cached.bytes
        }

        guard let bytes = resourceBytes(for: asset) else {
            // Not cached: the heuristic is cheap, and a later read may find the size.
            return heuristicBytes(pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight)
        }
        cache.withLock {
            $0.entries[identifier] = CacheEntry(modificationDate: modificationDate, bytes: bytes)
            $0.generation += 1
        }
        return bytes
    }

    /// Changes each time a size is measured. Compare it with the value seen at the
    /// last save to skip writing an unchanged store.
    public static var generation: Int {
        cache.withLock { $0.generation }
    }

    /// Loads persisted sizes into the cache. A record never replaces a size already
    /// measured in this process, and seeding does not change ``generation``.
    public static func seed(_ records: [AssetByteSizeRecord]) {
        cache.withLock { state in
            for record in records where state.entries[record.localIdentifier] == nil {
                state.entries[record.localIdentifier] = CacheEntry(
                    modificationDate: record.modificationDate,
                    bytes: record.bytes
                )
            }
        }
    }

    /// Caches a size measured outside ``bytes(for:)`` — a test double standing in
    /// for PhotoKit — and advances ``generation`` like any other measurement.
    public static func record(_ measured: AssetByteSizeRecord) {
        cache.withLock { state in
            state.entries[measured.localIdentifier] = CacheEntry(
                modificationDate: measured.modificationDate,
                bytes: measured.bytes
            )
            state.generation += 1
        }
    }

    /// Cached sizes for `identifiers`, in identifier order, ready to persist.
    /// Identifiers without a measured size are left out.
    public static func records(for identifiers: some Sequence<String>) -> [AssetByteSizeRecord] {
        let sortedIdentifiers = Set(identifiers).sorted()
        return cache.withLock { state in
            sortedIdentifiers.compactMap { identifier in
                state.entries[identifier].map {
                    AssetByteSizeRecord(
                        localIdentifier: identifier,
                        modificationDate: $0.modificationDate,
                        bytes: $0.bytes
                    )
                }
            }
        }
    }

    /// Resolves and caches bytes for `assets`, so later reads — including the ones
    /// on the main actor — only hit the cache. Call it off the main actor.
    public static func prewarm(_ assets: some Sequence<PHAsset>) {
        let startTime = ContinuousClock().now
        var count = 0
        for asset in assets {
            _ = bytes(for: asset)
            count += 1
        }
        let duration = startTime.duration(to: ContinuousClock().now)
        AppLog.scan.info("\(AppLog.tag(.cache, "Asset byte sizes warmed. assets=\(count) duration=\(duration)"))")
    }

    /// Bytes for assets that are only known by identifier, e.g. a persisted
    /// category. Identifiers PhotoKit no longer knows are absent from the result.
    public static func bytes(forLocalIdentifiers identifiers: [String]) -> [String: Int64] {
        guard !identifiers.isEmpty else { return [:] }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var result: [String: Int64] = [:]
        result.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            result[asset.localIdentifier] = bytes(for: asset)
        }
        return result
    }

    /// The pre-file-size estimate: 0.5 B per pixel, never below 1.
    public static func heuristicBytes(pixelWidth: Int, pixelHeight: Int) -> Int64 {
        let pixelArea = Int64(pixelWidth) * Int64(pixelHeight)
        return max(1, pixelArea / 2)
    }

    /// Persisted dates lose sub-second precision in JSON, so equality is within a
    /// second — the same rule the feature-print cache uses.
    private static func isSameModificationDate(_ cached: Date?, _ current: Date?) -> Bool {
        switch (cached, current) {
        case (nil, nil):
            return true
        case let (cached?, current?):
            return abs(cached.timeIntervalSince(current)) < 1
        default:
            return false
        }
    }

    private static func resourceBytes(for asset: PHAsset) -> Int64? {
        // `fileSize` is not a declared property of PHAssetResource; it is read
        // through KVC and treated as absent when PhotoKit does not provide it.
        let total = PHAssetResource.assetResources(for: asset).reduce(into: Int64(0)) { total, resource in
            if resource.responds(to: fileSizeSelector),
               let size = resource.value(forKey: "fileSize") as? NSNumber {
                total += max(0, size.int64Value)
            }
        }
        return total > 0 ? total : nil
    }
}

/// One measured size as it is persisted.
public struct AssetByteSizeRecord: Codable, Equatable, Sendable {
    public let localIdentifier: String
    public let modificationDate: Date?
    public let bytes: Int64

    public init(localIdentifier: String, modificationDate: Date?, bytes: Int64) {
        self.localIdentifier = localIdentifier
        self.modificationDate = modificationDate
        self.bytes = bytes
    }
}
