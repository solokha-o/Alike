#if DEBUG
import Core
import os
import Photos
import UIKit

/// Real `PHAsset`s for the fake library.
///
/// `PhotoCluster` holds `PHAsset`s and every thumbnail loads through PhotoKit, so a
/// fake group needs photos that exist in the library. On the simulator this store
/// draws them into its own album once. On a device it never writes: it reads the
/// newest photos of the library instead.
nonisolated enum FakeLibraryPhotoStore {
    static let albumTitle = "Alike Fake Library"
    /// Enough for the largest scenario (57 photos for 55 groups, plus categories).
    static let seededPhotoCount = 64
    /// Photos in one drawn series: the same scene with small changes, like a burst.
    static let photosPerSeries = 4

    /// Photos for the fake library, oldest first, so every run shows the same order.
    static func assets(minimumCount: Int, requestsAccess: Bool = true) async -> [PHAsset] {
        guard await hasReadWriteAccess(requestsAccess: requestsAccess) else {
            AppLog.photoKit.error("Fake library: no photo access, so the groups stay empty")
            return []
        }
#if targetEnvironment(simulator)
        if albumAssets().count < minimumCount {
            do {
                try await seedAlbum()
            } catch {
                AppLog.photoKit.error("Fake library: seeding failed: \(error.localizedDescription)")
            }
        }
        let assets = albumAssets()
#else
        let assets = newestLibraryAssets(limit: max(minimumCount, seededPhotoCount))
#endif
        if assets.count < minimumCount {
            AppLog.photoKit.error("Fake library: \(assets.count) photos, \(minimumCount) needed")
        }
        return assets
    }

    private static func hasReadWriteAccess(requestsAccess: Bool) async -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined, requestsAccess {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        return status == .authorized || status == .limited
    }

    private static func album() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", albumTitle)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
            .firstObject
    }

    private static func albumAssets() -> [PHAsset] {
        guard let album = album() else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(in: album, options: options)
        return (0 ..< result.count).map { result.object(at: $0) }
    }

#if !targetEnvironment(simulator)
    private static func newestLibraryAssets(limit: Int) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.fetchLimit = limit
        let result = PHAsset.fetchAssets(with: options)
        return (0 ..< result.count).map { result.object(at: $0) }.reversed()
    }
#endif

#if targetEnvironment(simulator)
    /// Adds the drawn photos to a new album. Simulator only: a device library is
    /// never written.
    private static func seedAlbum() async throws {
        let existingAlbum = album()
        let start = albumAssets().count
        guard start < seededPhotoCount else { return }
        let photos = (start ..< seededPhotoCount).map { index in
            (index, photoData(index: index))
        }
        let baseDate = Date(timeIntervalSince1970: 1_790_000_000)
        try await PHPhotoLibrary.shared().performChanges {
            let albumRequest: PHAssetCollectionChangeRequest? =
                if let existingAlbum {
                    PHAssetCollectionChangeRequest(for: existingAlbum)
                } else {
                    PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                }
            var placeholders: [PHObjectPlaceholder] = []
            for (index, data) in photos {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
                request.creationDate = baseDate.addingTimeInterval(Double(index) * 60)
                if let placeholder = request.placeholderForCreatedAsset {
                    placeholders.append(placeholder)
                }
            }
            albumRequest?.addAssets(placeholders as NSArray)
        }
    }
#endif

    /// A deterministic landscape: each series shares sky, sun and hills, and each
    /// photo in it moves the sun and tints the light a little.
    static func photoData(index: Int) -> Data {
        let series = index / photosPerSeries
        let variant = index % photosPerSeries
        let size = CGSize(width: 1_200, height: 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cgContext = context.cgContext
            let hue = CGFloat((series * 37) % 100) / 100
            let light = CGFloat(variant) * 0.04
            let colors = [
                UIColor(hue: hue, saturation: 0.55, brightness: 0.95 - light, alpha: 1).cgColor,
                UIColor(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.35, brightness: 1, alpha: 1).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }

            let sunX = size.width * (0.25 + 0.15 * CGFloat(variant) + 0.05 * CGFloat(series % 3))
            UIColor(white: 1, alpha: 0.85).setFill()
            cgContext.fillEllipse(in: CGRect(x: sunX - 70, y: 180, width: 140, height: 140))

            let hillColor = UIColor(hue: (hue + 0.35).truncatingRemainder(dividingBy: 1), saturation: 0.5, brightness: 0.45, alpha: 1)
            hillColor.setFill()
            let hills = UIBezierPath()
            hills.move(to: CGPoint(x: 0, y: size.height))
            hills.addLine(to: CGPoint(x: 0, y: size.height * 0.62))
            hills.addCurve(
                to: CGPoint(x: size.width, y: size.height * (0.58 + 0.04 * CGFloat(series % 2))),
                controlPoint1: CGPoint(x: size.width * 0.3, y: size.height * 0.45),
                controlPoint2: CGPoint(x: size.width * 0.6, y: size.height * 0.8)
            )
            hills.addLine(to: CGPoint(x: size.width, y: size.height))
            hills.close()
            hills.fill()
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
}
#endif
