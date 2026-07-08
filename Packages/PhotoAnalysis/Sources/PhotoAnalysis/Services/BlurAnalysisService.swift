import Core
import CoreGraphics
import Foundation
@preconcurrency import Photos
#if canImport(UIKit)
import UIKit
#endif

struct BlurAnalysisAssetSnapshot: Equatable, Sendable {
    let localIdentifier: String
    let isScreenshot: Bool
    let isFavorite: Bool
    let estimatedCleanupBytes: Int64
}

struct BlurAnalysisCandidate: Equatable, Sendable {
    let localIdentifier: String
    let sharpnessScore: Double
    let estimatedCleanupBytes: Int64
}

enum BlurCandidateSelector {
    static let maxWorstPercentile = 0.08
    static let absoluteSharpnessFloor = 10.0
    static let relativeToMedianMultiplier = 0.55
    static let minimumPopulation = 12

    static func selectCandidates(from candidates: [BlurAnalysisCandidate]) -> [BlurAnalysisCandidate] {
        guard candidates.count >= minimumPopulation else { return [] }

        let sorted = candidates.sorted {
            if $0.sharpnessScore != $1.sharpnessScore {
                return $0.sharpnessScore < $1.sharpnessScore
            }
            if $0.estimatedCleanupBytes != $1.estimatedCleanupBytes {
                return $0.estimatedCleanupBytes > $1.estimatedCleanupBytes
            }
            return $0.localIdentifier < $1.localIdentifier
        }

        let medianSharpness = medianScore(from: sorted)
        let adaptiveFloor = min(absoluteSharpnessFloor, medianSharpness * relativeToMedianMultiplier)
        let worstCount = Int(floor(Double(sorted.count) * maxWorstPercentile))
        guard worstCount > 0 else { return [] }

        return Array(sorted.prefix(worstCount)).filter { $0.sharpnessScore <= adaptiveFloor }
    }

    private static func medianScore(from sorted: [BlurAnalysisCandidate]) -> Double {
        let middleIndex = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middleIndex - 1].sharpnessScore + sorted[middleIndex].sharpnessScore) / 2
        }
        return sorted[middleIndex].sharpnessScore
    }
}

struct BlurSharpnessScorer {
    func score(image: CGImage) -> Double {
        guard let pixels = grayscalePixels(from: image, dimension: 64) else {
            return .greatestFiniteMagnitude
        }
        guard pixels.width > 2, pixels.height > 2 else {
            return .greatestFiniteMagnitude
        }

        var total: Double = 0
        var sampleCount = 0

        for y in 1..<(pixels.height - 1) {
            for x in 1..<(pixels.width - 1) {
                let center = Double(pixels[x, y])
                let laplacian = abs(
                    4 * center
                    - Double(pixels[x - 1, y])
                    - Double(pixels[x + 1, y])
                    - Double(pixels[x, y - 1])
                    - Double(pixels[x, y + 1])
                )
                total += laplacian
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return .greatestFiniteMagnitude }
        return total / Double(sampleCount)
    }

    private func grayscalePixels(from image: CGImage, dimension: Int) -> GrayscalePixels? {
        let width = dimension
        let height = dimension
        let bytesPerRow = width
        var data = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return GrayscalePixels(width: width, height: height, bytes: data)
    }
}

struct BlurAnalysisService: Sendable {
    private static let thumbnailTargetSize = CGSize(width: 128, height: 128)

    private let scorer: BlurSharpnessScorer
    private let imageProvider: @MainActor @Sendable (PHAsset, CGSize) async throws -> CGImage?

    init(
        scorer: BlurSharpnessScorer = BlurSharpnessScorer(),
        imageProvider: @escaping @MainActor @Sendable (PHAsset, CGSize) async throws -> CGImage? = Self.defaultImageProvider
    ) {
        self.scorer = scorer
        self.imageProvider = imageProvider
    }

    func makeSnapshot(from assets: [PHAsset]) async throws -> CleanupCategorySnapshot? {
        var candidates: [BlurAnalysisCandidate] = []

        for asset in assets {
            try Task.checkCancellation()
            guard !asset.mediaSubtypes.contains(.photoScreenshot), !asset.isFavorite else {
                continue
            }

            guard let image = try await imageProvider(asset, Self.thumbnailTargetSize) else {
                continue
            }

            let sharpness = scorer.score(image: image)
            guard sharpness.isFinite else { continue }

            candidates.append(
                BlurAnalysisCandidate(
                    localIdentifier: asset.localIdentifier,
                    sharpnessScore: sharpness,
                    estimatedCleanupBytes: asset.estimatedCleanupBytes
                )
            )
        }

        let selected = BlurCandidateSelector.selectCandidates(from: candidates)
        guard !selected.isEmpty else { return nil }

        return CleanupCategorySnapshot(
            kind: .blurredPhotos,
            localIdentifiers: selected.map(\.localIdentifier),
            assetCount: selected.count,
            estimatedSavingsBytes: selected.reduce(into: Int64(0)) { $0 += $1.estimatedCleanupBytes }
        )
    }
}

private struct GrayscalePixels: Sendable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    subscript(_ x: Int, _ y: Int) -> UInt8 {
        bytes[(y * width) + x]
    }
}

private extension BlurAnalysisService {
    @MainActor
    static func defaultImageProvider(asset: PHAsset, targetSize: CGSize) async throws -> CGImage? {
        #if canImport(UIKit)
        return try await asset.loadImage(targetSize: targetSize)?.cgImage
        #else
        return nil
        #endif
    }
}
