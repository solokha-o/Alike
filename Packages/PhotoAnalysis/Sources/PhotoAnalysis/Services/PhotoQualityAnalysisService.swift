import Core
import CoreGraphics
import Foundation
import os
@preconcurrency import Photos
import Vision

/// Measures the technical quality of photos for Best Shot ranking.
///
/// It only *measures*: every threshold and weight lives in
/// `PhotoQualityScoringConfig`, and turning signals into a winner is
/// `BestShotRanker`'s job. One unreadable photo is recorded as an
/// `analysisFailure` instead of failing the whole batch.
struct PhotoQualityAnalysisService: PhotoQualityAnalyzing {
    private let config: PhotoQualityScoringConfig
    private let scorer: BlurSharpnessScorer
    private let imageProvider: @Sendable (PHAsset, CGSize) async throws -> CGImage?
    private let faceDetector: @Sendable (CGImage) throws -> [VNFaceObservation]

    init(
        config: PhotoQualityScoringConfig = .current,
        scorer: BlurSharpnessScorer = BlurSharpnessScorer(),
        imageProvider: @escaping @Sendable (PHAsset, CGSize) async throws -> CGImage?
            = AnalysisImageProvider.requestImage,
        faceDetector: @escaping @Sendable (CGImage) throws -> [VNFaceObservation]
            = PhotoQualityAnalysisService.detectFaces
    ) {
        self.config = config
        self.scorer = scorer
        self.imageProvider = imageProvider
        self.faceDetector = faceDetector
    }

    func scores(for assets: [PHAsset]) async throws -> [PhotoQualityScore] {
        let workItems = assets.map { asset in
            QualityWorkItem(
                asset: asset,
                localIdentifier: asset.localIdentifier,
                modificationDate: asset.modificationDate,
                pixelArea: Int64(asset.pixelWidth) * Int64(asset.pixelHeight)
            )
        }
        guard !workItems.isEmpty else { return [] }

        let config = self.config
        let imageProvider = self.imageProvider
        let analyze = makeAnalyzer()

        return try await ImageAnalysisTaskPool.compactMap(
            workItems,
            maxConcurrentTasks: config.maxConcurrentAnalysisTasks
        ) { workItem in
            try Task.checkCancellation()
            let targetSide = CGFloat(config.analysisImageLongSide)
            let image = try? await imageProvider(
                workItem.asset,
                CGSize(width: targetSide, height: targetSide)
            )
            let signals: PhotoQualitySignals
            if let image {
                signals = analyze(image, workItem.pixelArea)
            } else {
                signals = .failed(.assetUnavailable, pixelArea: workItem.pixelArea)
            }
            return PhotoQualityScore(
                localIdentifier: workItem.localIdentifier,
                sourceModificationDate: workItem.modificationDate,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: signals
            )
        }
    }

    /// Measures one already-decoded image. Exposed for tests, which feed it
    /// synthesized `CGImage`s instead of a photo library.
    func signals(for image: CGImage, pixelArea: Int64) -> PhotoQualitySignals {
        makeAnalyzer()(image, pixelArea)
    }

    private func makeAnalyzer() -> @Sendable (CGImage, Int64) -> PhotoQualitySignals {
        let config = self.config
        let scorer = self.scorer
        let faceDetector = self.faceDetector

        return { image, pixelArea in
            guard max(image.width, image.height) >= config.minimumAnalysisLongSide else {
                return .failed(.tooSmallToAnalyze, pixelArea: pixelArea)
            }
            guard let pixels = GrayscaleImageSampler.sample(image, dimension: config.sharpnessGridSide) else {
                return .failed(.renderFailed, pixelArea: pixelArea)
            }

            let globalSharpness = scorer.score(pixels: pixels)
            let exposure = ExposureMeasurement(pixels: pixels, config: config)
            let noise = Self.noiseEstimate(pixels: pixels)

            let detectedFaces = Self.detectedFaces(
                in: image,
                detector: faceDetector,
                scorer: scorer,
                config: config
            )
            let faces = detectedFaces.map(\.signal)
            // The main face is the subject: measuring sharpness and contrast on
            // it is what stops a sharp background from masking a blurred person.
            let mainFace = detectedFaces.max { $0.signal.sharpness < $1.signal.sharpness }
            let subjectSharpness = mainFace?.signal.sharpness
            let subjectContrast = mainFace.flatMap { face in
                image.cropping(to: face.rect)
                    .flatMap { GrayscaleImageSampler.sample($0, dimension: config.sharpnessGridSide) }
                    .map { ExposureMeasurement(pixels: $0, config: config).lumaStdDev }
            } ?? exposure.lumaStdDev

            return PhotoQualitySignals(
                globalSharpness: globalSharpness.isFinite ? globalSharpness : 0,
                subjectSharpness: subjectSharpness,
                darkClippedFraction: exposure.darkClippedFraction,
                brightClippedFraction: exposure.brightClippedFraction,
                subjectLumaStdDev: subjectContrast,
                noiseEstimate: noise,
                faceSignals: faces,
                pixelArea: pixelArea
            )
        }
    }

    // MARK: - Faces

    /// Classic Vision request: the deployment target is iOS 17, so the Swift
    /// Vision API introduced in iOS 18 is not available here.
    static func detectFaces(in image: CGImage) throws -> [VNFaceObservation] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return request.results ?? []
    }

    private static func detectedFaces(
        in image: CGImage,
        detector: @Sendable (CGImage) throws -> [VNFaceObservation],
        scorer: BlurSharpnessScorer,
        config: PhotoQualityScoringConfig
    ) -> [DetectedFace] {
        let observations: [VNFaceObservation]
        do {
            observations = try detector(image)
        } catch {
            AppLog.photoKit.debug(
                "\(AppLog.tag(.error, "Face detection failed, scoring without faces: \(error.localizedDescription)"))"
            )
            return []
        }

        return observations.compactMap { observation -> DetectedFace? in
            guard Double(observation.confidence) >= config.minimumFaceDetectionConfidence else { return nil }
            let rect = imageRect(for: observation.boundingBox, in: image)
            let side = max(rect.width, rect.height)
            guard side >= config.minimumFacePixelSize else { return nil }
            guard let crop = image.cropping(to: rect),
                  let pixels = GrayscaleImageSampler.sample(crop, dimension: config.sharpnessGridSide) else {
                return nil
            }

            let sharpness = scorer.score(pixels: pixels)
            return DetectedFace(
                signal: FaceQualitySignal(
                    detectionConfidence: Double(observation.confidence),
                    boxPixelSize: Double(side),
                    sharpness: sharpness.isFinite ? sharpness : 0,
                    hasClosedEyes: closedEyes(in: observation, config: config),
                    isCroppedByFrame: isCroppedByFrame(rect: rect, in: image)
                ),
                rect: rect
            )
        }
    }

    private static func imageRect(for boundingBox: CGRect, in image: CGImage) -> CGRect {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        // Vision's origin is bottom-left, CGImage cropping is top-left.
        let rect = CGRect(
            x: boundingBox.minX * width,
            y: (1 - boundingBox.maxY) * height,
            width: boundingBox.width * width,
            height: boundingBox.height * height
        )
        return rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static func isCroppedByFrame(rect: CGRect, in image: CGImage) -> Bool {
        let margin: CGFloat = 1
        return rect.minX <= margin
            || rect.minY <= margin
            || rect.maxX >= CGFloat(image.width) - margin
            || rect.maxY >= CGFloat(image.height) - margin
    }

    /// `nil` whenever the reading is not confident enough to act on, which the
    /// ranker treats as "unknown" rather than "eyes open".
    private static func closedEyes(
        in observation: VNFaceObservation,
        config: PhotoQualityScoringConfig
    ) -> Bool? {
        guard Double(observation.confidence) >= config.blinkConfidenceFloor,
              let landmarks = observation.landmarks,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye else {
            return nil
        }
        guard let left = eyeAspectRatio(leftEye), let right = eyeAspectRatio(rightEye) else {
            return nil
        }
        return max(left, right) < config.closedEyeAspectRatio
    }

    private static func eyeAspectRatio(_ region: VNFaceLandmarkRegion2D) -> Double? {
        let points = region.normalizedPoints
        guard points.count > 2 else { return nil }
        let xs = points.map { Double($0.x) }
        let ys = points.map { Double($0.y) }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }
        let width = maxX - minX
        guard width > .ulpOfOne else { return nil }
        return (maxY - minY) / width
    }

    // MARK: - Noise

    /// Noise floor: the mean absolute Laplacian of the flattest blocks, where
    /// there is no detail left for it to be confused with.
    private static func noiseEstimate(pixels: GrayscalePixels) -> Double {
        let blockSide = 8
        guard pixels.width >= blockSide * 2, pixels.height >= blockSide * 2 else { return 0 }

        var blockEnergies: [Double] = []
        var blockY = 1
        while blockY + blockSide < pixels.height {
            var blockX = 1
            while blockX + blockSide < pixels.width {
                var total: Double = 0
                var count = 0
                for y in blockY..<(blockY + blockSide) {
                    for x in blockX..<(blockX + blockSide) {
                        let laplacian = abs(
                            4 * Double(pixels[x, y])
                            - Double(pixels[x - 1, y])
                            - Double(pixels[x + 1, y])
                            - Double(pixels[x, y - 1])
                            - Double(pixels[x, y + 1])
                        )
                        total += laplacian
                        count += 1
                    }
                }
                if count > 0 { blockEnergies.append(total / Double(count)) }
                blockX += blockSide
            }
            blockY += blockSide
        }

        guard !blockEnergies.isEmpty else { return 0 }
        let sorted = blockEnergies.sorted()
        let quartileCount = max(1, sorted.count / 4)
        let flattest = sorted.prefix(quartileCount)
        return (flattest.reduce(0, +) / Double(quartileCount)) / 255.0
    }
}

/// Clipping and contrast, measured in one pass over the luma sample.
private struct ExposureMeasurement {
    let darkClippedFraction: Double
    let brightClippedFraction: Double
    let lumaStdDev: Double

    init(pixels: GrayscalePixels, config: PhotoQualityScoringConfig) {
        var dark = 0
        var bright = 0
        var total: Double = 0
        var totalSquared: Double = 0
        let count = pixels.width * pixels.height

        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let luma = pixels.luma(x, y)
                if luma <= config.darkClippingLuma { dark += 1 }
                if luma >= config.brightClippingLuma { bright += 1 }
                total += luma
                totalSquared += luma * luma
            }
        }

        guard count > 0 else {
            darkClippedFraction = 0
            brightClippedFraction = 0
            lumaStdDev = 0
            return
        }

        let mean = total / Double(count)
        let variance = max(0, totalSquared / Double(count) - mean * mean)
        darkClippedFraction = Double(dark) / Double(count)
        brightClippedFraction = Double(bright) / Double(count)
        lumaStdDev = variance.squareRoot()
    }
}

/// A face plus the rect it was measured on, so the subject region can be
/// reused for contrast without detecting twice.
private struct DetectedFace {
    let signal: FaceQualitySignal
    let rect: CGRect
}

private struct QualityWorkItem: @unchecked Sendable {
    let asset: PHAsset
    let localIdentifier: String
    let modificationDate: Date?
    let pixelArea: Int64
}
