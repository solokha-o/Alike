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

    private static let photosBundle = Bundle(for: PHAsset.self)
    private static let fileSizeSelector = NSSelectorFromString("fileSize")
    private static let cache = OSAllocatedUnfairLock(initialState: [String: CacheEntry]())

    public static func bytes(for asset: PHAsset) -> Int64 {
        let identifier = asset.localIdentifier
        let modificationDate = asset.modificationDate
        if let cached = cache.withLock({ $0[identifier] }),
           cached.modificationDate == modificationDate {
            return cached.bytes
        }

        guard let bytes = resourceBytes(for: asset) else {
            // Not cached: the heuristic is cheap, and a later read may find the size.
            return heuristicBytes(pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight)
        }
        cache.withLock {
            $0[identifier] = CacheEntry(modificationDate: modificationDate, bytes: bytes)
        }
        return bytes
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

    private static func resourceBytes(for asset: PHAsset) -> Int64? {
        // A PHAsset subclass defined outside Photos (a test double) has no library
        // object behind it; asking it for resources is not meaningful.
        guard Bundle(for: type(of: asset)) == photosBundle else { return nil }
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
