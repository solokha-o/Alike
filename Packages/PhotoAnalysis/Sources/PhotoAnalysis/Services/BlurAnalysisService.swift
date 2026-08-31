import Core
import CoreGraphics
import Foundation
import os
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
        let worstCount = max(1, Int(floor(Double(sorted.count) * maxWorstPercentile)))

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

/// Mean absolute Laplacian: the sharpness measure behind both the Blurred
/// Photos category and Best Shot scoring.
struct BlurSharpnessScorer {
    /// Default grid of the blur category. Best Shot scoring passes a larger
    /// dimension, because a 64 px grid is only good enough for a first pass.
    static let blurPassDimension = 64

    func score(image: CGImage, dimension: Int = Self.blurPassDimension) -> Double {
        guard let pixels = GrayscaleImageSampler.sample(image, dimension: dimension) else {
            return .greatestFiniteMagnitude
        }
        return score(pixels: pixels)
    }

    func score(pixels: GrayscalePixels) -> Double {
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
}

struct BlurAnalysisService: Sendable {
    private static let thumbnailTargetSize = CGSize(width: 128, height: 128)
    private static let maxConcurrentTasks = 4

    private let scorer: BlurSharpnessScorer
    private let imageProvider: @Sendable (PHAsset, CGSize) async throws -> CGImage?

    init(
        scorer: BlurSharpnessScorer = BlurSharpnessScorer(),
        imageProvider: @escaping @Sendable (PHAsset, CGSize) async throws -> CGImage? = AnalysisImageProvider.requestImage
    ) {
        self.scorer = scorer
        self.imageProvider = imageProvider
    }

    func makeSnapshot(
        from assets: [PHAsset],
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> CleanupCategorySnapshot? {
        let workItems = assets.compactMap { asset -> BlurAnalysisWorkItem? in
            guard !asset.mediaSubtypes.contains(.photoScreenshot), !asset.isFavorite else {
                return nil
            }
            return BlurAnalysisWorkItem(
                asset: asset,
                localIdentifier: asset.localIdentifier,
                estimatedCleanupBytes: asset.estimatedCleanupBytes
            )
        }

        let imageProvider = self.imageProvider
        let scorer = self.scorer
        let candidates: [BlurAnalysisCandidate] = try await ImageAnalysisTaskPool.compactMap(
            workItems,
            maxConcurrentTasks: Self.maxConcurrentTasks,
            progress: progress
        ) { workItem in
            guard let image = try await imageProvider(workItem.asset, Self.thumbnailTargetSize) else {
                return nil
            }

            let sharpness = scorer.score(image: image)
            guard sharpness.isFinite else { return nil }

            return BlurAnalysisCandidate(
                localIdentifier: workItem.localIdentifier,
                sharpnessScore: sharpness,
                estimatedCleanupBytes: workItem.estimatedCleanupBytes
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

private struct BlurAnalysisWorkItem: @unchecked Sendable {
    let asset: PHAsset
    let localIdentifier: String
    let estimatedCleanupBytes: Int64
}


