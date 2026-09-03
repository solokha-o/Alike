import Foundation

/// Why one asset could not be measured. A failure never removes the photo from
/// the cluster; it only makes it ineligible for an automatic Best Shot pick.
public enum PhotoQualityAnalysisFailure: String, Codable, Sendable, Equatable {
    /// The asset could not be fetched or decoded (deleted, iCloud-only, corrupt).
    case assetUnavailable
    /// The image is too small to produce a trustworthy sharpness reading.
    case tooSmallToAnalyze
    /// Rendering the analysis thumbnail failed.
    case renderFailed
}

/// One detected face inside the analysis image.
///
/// Raw, unweighted measurements only: the ranker turns them into a score, so
/// the weights can change without decoding a single photo again.
public struct FaceQualitySignal: Codable, Sendable, Equatable {
    /// Vision detection confidence, already filtered against the configured floor.
    public let detectionConfidence: Double
    /// Longest side of the face box in analysis-image pixels.
    public let boxPixelSize: Double
    /// Mean absolute Laplacian measured on the face crop alone.
    public let sharpness: Double
    /// `true` only when closed eyes were detected above the blink confidence
    /// floor; `nil` means "not confidently known", which the ranker ignores.
    public let hasClosedEyes: Bool?
    /// The face box touches the frame edge, so the face is cut off.
    public let isCroppedByFrame: Bool

    public init(
        detectionConfidence: Double,
        boxPixelSize: Double,
        sharpness: Double,
        hasClosedEyes: Bool?,
        isCroppedByFrame: Bool
    ) {
        self.detectionConfidence = detectionConfidence
        self.boxPixelSize = boxPixelSize
        self.sharpness = sharpness
        self.hasClosedEyes = hasClosedEyes
        self.isCroppedByFrame = isCroppedByFrame
    }
}

/// Raw technical measurements for one photo.
///
/// Nothing here is weighted or normalized: `BestShotRanker` does that against
/// the other photos of the same cluster, because an absolute threshold does not
/// hold across cameras and scenes.
public struct PhotoQualitySignals: Codable, Sendable, Equatable {
    /// Mean absolute Laplacian over the whole analysis image.
    public let globalSharpness: Double
    /// Same measure over the subject or main face region, when one was found.
    public let subjectSharpness: Double?
    /// Fraction of pixels at or below the dark clipping threshold.
    public let darkClippedFraction: Double
    /// Fraction of pixels at or above the bright clipping threshold.
    public let brightClippedFraction: Double
    /// Luma standard deviation of the subject region, normalized to 0…1.
    public let subjectLumaStdDev: Double
    /// High-frequency residual left after smoothing; higher means noisier.
    public let noiseEstimate: Double
    /// `nil` when face detection did not run; empty when it found nobody.
    public let faceSignals: [FaceQualitySignal]?
    public let pixelArea: Int64
    public let analysisFailure: PhotoQualityAnalysisFailure?

    public init(
        globalSharpness: Double = 0,
        subjectSharpness: Double? = nil,
        darkClippedFraction: Double = 0,
        brightClippedFraction: Double = 0,
        subjectLumaStdDev: Double = 0,
        noiseEstimate: Double = 0,
        faceSignals: [FaceQualitySignal]? = nil,
        pixelArea: Int64 = 0,
        analysisFailure: PhotoQualityAnalysisFailure? = nil
    ) {
        self.globalSharpness = globalSharpness
        self.subjectSharpness = subjectSharpness
        self.darkClippedFraction = darkClippedFraction
        self.brightClippedFraction = brightClippedFraction
        self.subjectLumaStdDev = subjectLumaStdDev
        self.noiseEstimate = noiseEstimate
        self.faceSignals = faceSignals
        self.pixelArea = pixelArea
        self.analysisFailure = analysisFailure
    }

    /// Signals for an asset that could not be measured at all.
    public static func failed(_ failure: PhotoQualityAnalysisFailure, pixelArea: Int64 = 0) -> PhotoQualitySignals {
        PhotoQualitySignals(pixelArea: pixelArea, analysisFailure: failure)
    }

    public var isUsable: Bool {
        analysisFailure == nil && globalSharpness.isFinite
    }

    /// Faces that actually carry a usable signal.
    public var usableFaceSignals: [FaceQualitySignal] {
        faceSignals ?? []
    }

    public var hasFaces: Bool {
        !usableFaceSignals.isEmpty
    }

    /// Total clipped fraction; the ranker penalizes both ends of the histogram.
    public var clippedFraction: Double {
        darkClippedFraction + brightClippedFraction
    }
}
