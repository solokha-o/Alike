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
            = AnalysisImageProvider.requestPreciseImage,
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
        let faceDetector = self.faceDetector
        let analyze = makeAnalyzer()

        return try await ImageAnalysisTaskPool.compactMap(
            workItems,
            maxConcurrentTasks: config.maxConcurrentAnalysisTasks
        ) { workItem in
            try Task.checkCancellation()
            let image = try? await imageProvider(
                workItem.asset,
                Self.squareSize(config.analysisImageLongSide)
            )
            let signals: PhotoQualitySignals
            if let image {
                // Two passes. The first is a probe on the thumbnail everything
                // else is measured on: who is in this photo, and how much of
                // the frame does the smallest of them take. Only if somebody
                // survives that gate does the second pass pay for a larger
                // image — a landscape with nobody in it costs exactly what it
                // cost before.
                let probe = Self.isLargeEnoughToAnalyze(image, config: config)
                    ? Self.probeFaces(in: image, detector: faceDetector, config: config)
                    : .empty
                let faceSource = await Self.faceSource(
                    for: workItem.asset,
                    probe: probe,
                    imageProvider: imageProvider,
                    config: config
                )
                signals = analyze(image, faceSource, probe, workItem.pixelArea)
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
        signals(for: image, faceSource: nil, pixelArea: pixelArea)
    }

    /// Same, with an explicit face-measurement image. `nil` means "measure the
    /// faces on the analysis image itself", which is both the fallback used
    /// when the second image request fails and the seam the tests drive.
    func signals(for image: CGImage, faceSource: CGImage?, pixelArea: Int64) -> PhotoQualitySignals {
        let probe = Self.probeFaces(in: image, detector: faceDetector, config: config)
        return makeAnalyzer()(image, faceSource, probe, pixelArea)
    }

    private static func squareSize(_ side: Int) -> CGSize {
        CGSize(width: CGFloat(side), height: CGFloat(side))
    }

    /// The gate `makeAnalyzer` fails on, checked before the probe as well: a
    /// photo that is about to be recorded as `tooSmallToAnalyze` must not pay
    /// for face detection or a face-source request first.
    private static func isLargeEnoughToAnalyze(
        _ image: CGImage,
        config: PhotoQualityScoringConfig
    ) -> Bool {
        max(image.width, image.height) >= config.minimumAnalysisLongSide
    }

    private func makeAnalyzer() -> @Sendable (CGImage, CGImage?, FaceProbe, Int64) -> PhotoQualitySignals {
        let config = self.config
        let scorer = self.scorer
        let faceDetector = self.faceDetector

        return { image, faceSource, probe, pixelArea in
            guard Self.isLargeEnoughToAnalyze(image, config: config) else {
                return .failed(.tooSmallToAnalyze, pixelArea: pixelArea)
            }
            guard let pixels = GrayscaleImageSampler.sample(image, dimension: config.sharpnessGridSide) else {
                return .failed(.renderFailed, pixelArea: pixelArea)
            }

            let globalSharpness = scorer.score(pixels: pixels)
            let exposure = ExposureMeasurement(pixels: pixels, config: config)
            let noise = Self.noiseEstimate(pixels: pixels)

            let measurement = Self.measureFaces(
                analysisImage: image,
                faceSource: faceSource,
                probe: probe,
                detector: faceDetector,
                scorer: scorer,
                config: config
            )
            let detectedFaces = measurement.faces
            let faces = detectedFaces.map(\.signal)
            // The main face is the subject: measuring sharpness and contrast on
            // it is what stops a sharp background from masking a blurred person.
            //
            // Chosen by how much of the frame it occupies, never by how sharp it
            // is — picking the sharpest face would let a small, crisp bystander
            // in the background speak for a blurred subject in front, which is
            // precisely the case this scoring exists to catch.
            let mainFace = detectedFaces.max { lhs, rhs in
                let lhsArea = lhs.rect.width * lhs.rect.height
                let rhsArea = rhs.rect.width * rhs.rect.height
                if lhsArea != rhsArea { return lhsArea < rhsArea }
                return lhs.signal.detectionConfidence < rhs.signal.detectionConfidence
            }
            let subjectSharpness = mainFace?.signal.sharpness
            let subjectContrast = mainFace.flatMap { face in
                measurement.image.cropping(to: face.rect)
                    .flatMap { GrayscaleImageSampler.sample($0, dimension: config.faceCropSide) }
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
                rejectedFaceCounts: measurement.rejections,
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

    /// Pass 1: who is in this photo, which of them are worth measuring, and how
    /// much of the frame the smallest of those takes.
    ///
    /// The gate is a fraction of the long side rather than a pixel count. The
    /// old absolute gate of 64 pixels was applied to a 256-pixel analysis
    /// image, so it demanded a quarter of the frame and rejected essentially
    /// every real face; a fraction says the same thing about relevance without
    /// silently depending on the thumbnail size.
    static func probeFaces(
        in image: CGImage,
        detector: @Sendable (CGImage) throws -> [VNFaceObservation],
        config: PhotoQualityScoringConfig
    ) -> FaceProbe {
        let observations: [VNFaceObservation]
        do {
            observations = try detector(image)
        } catch {
            AppLog.photoKit.debug(
                "\(AppLog.tag(.error, "Face detection failed, scoring without faces: \(error.localizedDescription)"))"
            )
            // A detector that threw measured nothing, so it rejected nothing
            // either. That is a different state from "we looked and said no".
            return .empty
        }

        var accepted: [VNFaceObservation] = []
        var lowConfidence = 0
        var tooSmall = 0
        var smallestFraction: Double?

        for observation in observations {
            guard Double(observation.confidence) >= config.minimumFaceDetectionConfidence else {
                lowConfidence += 1
                continue
            }
            let fraction = frameFraction(of: observation.boundingBox, in: image)
            guard fraction >= config.minimumFaceFrameFraction else {
                tooSmall += 1
                continue
            }
            accepted.append(observation)
            smallestFraction = min(smallestFraction ?? fraction, fraction)
        }

        return FaceProbe(
            accepted: accepted,
            rejections: FaceRejectionCounts(lowConfidence: lowConfidence, tooSmallInFrame: tooSmall),
            smallestAcceptedFraction: smallestFraction
        )
    }

    /// Long side of the face box as a fraction of the image's long side.
    private static func frameFraction(of boundingBox: CGRect, in image: CGImage) -> Double {
        let width = Double(image.width)
        let height = Double(image.height)
        let longSide = max(width, height)
        guard longSide > 0 else { return 0 }
        let boxLongSide = max(Double(boundingBox.width) * width, Double(boundingBox.height) * height)
        return boxLongSide / longSide
    }

    /// Pass 2's image: large enough that the smallest accepted face still has
    /// `faceCropSide` real pixels to be measured on. `nil` whenever the
    /// analysis image already suffices, nobody survived the probe, or the
    /// request failed — all three mean "measure on what we already have".
    private static func faceSource(
        for asset: PHAsset,
        probe: FaceProbe,
        imageProvider: @Sendable (PHAsset, CGSize) async throws -> CGImage?,
        config: PhotoQualityScoringConfig
    ) async -> CGImage? {
        guard let fraction = probe.smallestAcceptedFraction else { return nil }
        let side = config.faceSourceLongSide(smallestAcceptedFaceFraction: fraction)
        guard side > config.analysisImageLongSide else { return nil }

        let image = try? await imageProvider(asset, squareSize(side))
        if image == nil {
            AppLog.photoKit.debug(
                "\(AppLog.tag(.photokit, "Face source image at \(side) px unavailable, measuring faces on the analysis image"))"
            )
        }
        return image
    }

    /// Pass 2: measure the accepted faces on real pixels.
    ///
    /// When a face source was fetched, detection is re-run on it — landmarks
    /// read off a 12-pixel face decide blinks about as well as sharpness does —
    /// and its result is used whenever it still finds somebody. Otherwise the
    /// probe's own observations stand, measured on the analysis image.
    private static func measureFaces(
        analysisImage: CGImage,
        faceSource: CGImage?,
        probe: FaceProbe,
        detector: @Sendable (CGImage) throws -> [VNFaceObservation],
        scorer: BlurSharpnessScorer,
        config: PhotoQualityScoringConfig
    ) -> (faces: [DetectedFace], rejections: FaceRejectionCounts, image: CGImage) {
        var image = analysisImage
        var observations = probe.accepted
        var rejections = probe.rejections

        if let faceSource {
            let reprobe = probeFaces(in: faceSource, detector: detector, config: config)
            if !reprobe.accepted.isEmpty {
                image = faceSource
                observations = reprobe.accepted
                rejections = reprobe.rejections
            }
        }

        guard !observations.isEmpty else { return ([], rejections, image) }

        let analysisLongSide = Double(max(analysisImage.width, analysisImage.height))
        var faces: [DetectedFace] = []
        var insufficientResolution = 0
        var cropFailed = 0

        for observation in observations {
            let rect = imageRect(for: observation.boundingBox, in: image)
            let sourceSide = max(rect.width, rect.height)
            // Never interpolate a face up to the grid: a crop stretched from 12
            // pixels to the sampling side measures the interpolator, not the
            // face, which is exactly the reading that made lowering the old
            // gate pointless.
            guard Double(sourceSide) >= Double(config.faceCropSide) else {
                insufficientResolution += 1
                continue
            }
            guard let crop = image.cropping(to: rect),
                  let pixels = GrayscaleImageSampler.sample(crop, dimension: config.faceCropSide) else {
                cropFailed += 1
                continue
            }

            let sharpness = scorer.score(pixels: pixels)
            faces.append(
                DetectedFace(
                    signal: FaceQualitySignal(
                        detectionConfidence: Double(observation.confidence),
                        boxPixelSize: frameFraction(of: observation.boundingBox, in: image) * analysisLongSide,
                        sourcePixelSize: Double(sourceSide),
                        sharpness: sharpness.isFinite ? sharpness : 0,
                        hasClosedEyes: closedEyes(in: observation, config: config),
                        isCroppedByFrame: isCroppedByFrame(rect: rect, in: image)
                    ),
                    rect: rect
                )
            )
        }

        rejections = rejections + FaceRejectionCounts(
            insufficientResolution: insufficientResolution,
            cropFailed: cropFailed
        )
        return (faces, rejections, image)
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

/// What pass 1 learned: who is worth measuring, who was turned away and why,
/// and how large the measurement image has to be for the smallest survivor.
struct FaceProbe: @unchecked Sendable {
    let accepted: [VNFaceObservation]
    let rejections: FaceRejectionCounts
    /// Long-side fraction of the smallest accepted face; `nil` when none was.
    let smallestAcceptedFraction: Double?

    /// Nobody was looked for, so nobody was found or turned away.
    static let empty = FaceProbe(accepted: [], rejections: .empty, smallestAcceptedFraction: nil)
}
// `VNFaceObservation` is an immutable Vision result object that is never
// mutated after detection, which is why the probe crosses the concurrency
// boundary unchecked — the same reason `QualityWorkItem` carries a `PHAsset`.

private struct QualityWorkItem: @unchecked Sendable {
    let asset: PHAsset
    let localIdentifier: String
    let modificationDate: Date?
    let pixelArea: Int64
}
