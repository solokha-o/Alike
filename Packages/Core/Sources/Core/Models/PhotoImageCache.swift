import Foundation

struct PhotoImageCacheKey: Hashable, Sendable {
    let assetIdentifier: String
    let modificationTimestamp: UInt64?
    let targetWidth: UInt64
    let targetHeight: UInt64

    init(assetIdentifier: String, modificationDate: Date?, targetSize: CGSize) {
        self.assetIdentifier = assetIdentifier
        self.modificationTimestamp = modificationDate.map {
            $0.timeIntervalSinceReferenceDate.bitPattern
        }
        self.targetWidth = Double(targetSize.width).bitPattern
        self.targetHeight = Double(targetSize.height).bitPattern
    }
}

enum PhotoImageCacheCostPolicy {
    static func byteCost(bytesPerRow: Int, height: Int) -> Int {
        guard bytesPerRow > 0, height > 0 else { return 0 }
        guard bytesPerRow <= Int.max / height else { return Int.max }
        return bytesPerRow * height
    }
}

#if canImport(UIKit)
import UIKit

@MainActor
final class PhotoImageCache {
    static let shared = PhotoImageCache()

    private enum Defaults {
        static let totalCostLimit = 128 * 1_024 * 1_024
        static let countLimit = 256
    }

    private let cache = NSCache<PhotoImageCacheKeyBox, UIImage>()

    init(
        totalCostLimit: Int = Defaults.totalCostLimit,
        countLimit: Int = Defaults.countLimit
    ) {
        cache.totalCostLimit = totalCostLimit
        cache.countLimit = countLimit
    }

    func image(for key: PhotoImageCacheKey) -> UIImage? {
        cache.object(forKey: PhotoImageCacheKeyBox(key))
    }

    func insert(_ image: UIImage, for key: PhotoImageCacheKey) {
        cache.setObject(
            image,
            forKey: PhotoImageCacheKeyBox(key),
            cost: imageCacheCost(image)
        )
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    private func imageCacheCost(_ image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return PhotoImageCacheCostPolicy.byteCost(
                bytesPerRow: cgImage.bytesPerRow,
                height: cgImage.height
            )
        }

        let pixelWidth = Int((image.size.width * image.scale).rounded(.up))
        let pixelHeight = Int((image.size.height * image.scale).rounded(.up))
        let bytesPerRow = PhotoImageCacheCostPolicy.byteCost(
            bytesPerRow: pixelWidth,
            height: 4
        )
        return PhotoImageCacheCostPolicy.byteCost(
            bytesPerRow: bytesPerRow,
            height: pixelHeight
        )
    }
}

private final class PhotoImageCacheKeyBox: NSObject {
    let key: PhotoImageCacheKey

    init(_ key: PhotoImageCacheKey) {
        self.key = key
    }

    override var hash: Int {
        key.hashValue
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PhotoImageCacheKeyBox else { return false }
        return key == other.key
    }
}
#endif
