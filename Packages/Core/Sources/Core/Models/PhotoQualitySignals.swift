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

/// Why a detected face never became a `FaceQualitySignal`.
///
/// Counted rather than discarded silently: "nobody is in this photo" and "there
/// are faces and we threw them away" used to be the same empty array, which is
/// why a gate that rejected every real face went unnoticed until someone went
/// looking for it by hand.
public struct FaceRejectionCounts: Codable, Sendable, Equatable {
    /// Vision's own confidence was below `minimumFaceDetectionConfidence`.
    public let lowConfidence: Int
    /// The face occupied less of the frame than `minimumFaceFrameFraction`.
    public let tooSmallInFrame: Int
    /// The face passed the frame gate, but even the face-source image could not
    /// supply `faceCropSide` real pixels for it.
    public let insufficientResolution: Int
    /// Cropping or grayscale sampling failed.
    public let cropFailed: Int

    public init(
        lowConfidence: Int = 0,
        tooSmallInFrame: Int = 0,
        insufficientResolution: Int = 0,
        cropFailed: Int = 0
    ) {
        self.lowConfidence = lowConfidence
        self.tooSmallInFrame = tooSmallInFrame
        self.insufficientResolution = insufficientResolution
        self.cropFailed = cropFailed
    }

    /// Nothing was rejected. Deliberately not called `none`: this type is
    /// almost always seen through an `Optional`, where `.none` would silently
    /// mean `nil` — "never measured" — instead of "measured, rejected nobody".
    public static let empty = FaceRejectionCounts()

    public var total: Int {
        lowConfidence + tooSmallInFrame + insufficientResolution + cropFailed
    }

    public var isEmpty: Bool { total == 0 }

    public static func + (lhs: FaceRejectionCounts, rhs: FaceRejectionCounts) -> FaceRejectionCounts {
        FaceRejectionCounts(
            lowConfidence: lhs.lowConfidence + rhs.lowConfidence,
            tooSmallInFrame: lhs.tooSmallInFrame + rhs.tooSmallInFrame,
            insufficientResolution: lhs.insufficientResolution + rhs.insufficientResolution,
            cropFailed: lhs.cropFailed + rhs.cropFailed
        )
    }
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
    /// Longest side of the face box in the pixels it was actually *measured* on,
    /// which is the face-source image and not the analysis frame.
    ///
    /// Optional because measurements written before the face source existed do
    /// not know it. It is what makes "sharpness came from real pixels" a fact
    /// that can be checked in an export rather than a claim.
    public let sourcePixelSize: Double?
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
        sourcePixelSize: Double? = nil,
        sharpness: Double,
        hasClosedEyes: Bool?,
        isCroppedByFrame: Bool
    ) {
        self.detectionConfidence = detectionConfidence
        self.boxPixelSize = boxPixelSize
        self.sourcePixelSize = sourcePixelSize
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
    /// `nil` when face detection did not run; empty when it found nobody *or*
    /// when every face it found was rejected — `rejectedFaceCounts` is what
    /// tells those two apart.
    public let faceSignals: [FaceQualitySignal]?
    /// Faces Vision found that never became a signal, by reason. `nil` for
    /// measurements written before the counts existed.
    public let rejectedFaceCounts: FaceRejectionCounts?
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
        rejectedFaceCounts: FaceRejectionCounts? = nil,
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
        self.rejectedFaceCounts = rejectedFaceCounts
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

    /// Faces were found and none of them survived the gates. Distinct from
    /// "there is nobody in this photo", and the signal to look at before
    /// concluding that face scoring simply does not apply here.
    public var hasOnlyRejectedFaces: Bool {
        !hasFaces && (rejectedFaceCounts?.isEmpty == false)
    }

    /// Total clipped fraction; the ranker penalizes both ends of the histogram.
    public var clippedFraction: Double {
        darkClippedFraction + brightClippedFraction
    }
}
