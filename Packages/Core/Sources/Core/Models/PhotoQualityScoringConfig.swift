import Foundation

/// Every threshold, weight and cut-off of Best Shot scoring, in one versioned
/// place. Nothing in the ranker or the analyzer may hardcode a number that
/// belongs here — the values are a starting point meant to be recalibrated on
/// real Alike clusters.
public struct PhotoQualityScoringConfig: Codable, Sendable, Equatable {
    // MARK: - Versions

    /// Bumped whenever the formula or the weights change; cached scores with a
    /// different version are a cache miss.
    public var scoringModelVersion: Int
    /// Bumped whenever the analysis image geometry changes, which invalidates
    /// the raw signals themselves.
    public var thumbnailConfigVersion: Int

    // MARK: - Image preparation

    /// Long side of the global analysis thumbnail, in pixels.
    public var analysisImageLongSide: Int
    /// Square side of the subject/face crop, in pixels. Face signals are
    /// measured on this grid, the whole frame on `sharpnessGridSide`.
    public var faceCropSide: Int
    /// Below this long side a score is not trustworthy enough to rank on.
    public var minimumAnalysisLongSide: Int
    /// Sharpness is measured on a square grid of this size.
    public var sharpnessGridSide: Int
    public var maxConcurrentAnalysisTasks: Int

    // MARK: - Sharpness

    /// Absolute sharpness floor. A cluster where nothing reaches it is weak as
    /// a whole, and the ranking says so instead of crowning the least blurred
    /// of several blurred frames.
    public var absoluteSharpnessFloor: Double
    /// Ratio of a candidate's sharpness to the cluster median.
    public var criticalSharpnessRatio: Double
    public var strongPenaltySharpnessRatio: Double
    public var weakPenaltySharpnessRatio: Double
    /// A critically blurred candidate is only removed when the cluster holds a
    /// reference frame at or above this ratio.
    public var referenceSharpnessRatio: Double
    public var criticalSharpnessPenalty: Double
    public var strongSharpnessPenalty: Double
    public var weakSharpnessPenalty: Double
    /// Weight of the subject/face region inside the sharpness component; the
    /// rest goes to the whole frame, so a sharp background cannot mask a
    /// blurred person.
    public var subjectSharpnessWeight: Double
    /// Robust normalization range, as percentiles of the cluster.
    public var normalizationLowPercentile: Double
    public var normalizationHighPercentile: Double

    // MARK: - Exposure

    /// Luma at or below this (0…1) counts as crushed shadow.
    public var darkClippingLuma: Double
    /// Luma at or above this (0…1) counts as blown highlight.
    public var brightClippingLuma: Double
    /// Clipping up to this fraction is free.
    public var clippingFreeFraction: Double
    /// Clipping above this fraction is fully penalized.
    public var clippingFullPenaltyFraction: Double
    /// Above this fraction the exposure defect is critical.
    public var clippingCriticalFraction: Double
    /// Subject luma standard deviation below this is a flat, contrastless frame.
    public var lowContrastStdDev: Double
    public var lowContrastPenalty: Double

    // MARK: - Faces

    public var minimumFaceDetectionConfidence: Double
    /// Minimum face box side, in analysis-image pixels.
    public var minimumFacePixelSize: Double
    public var blinkConfidenceFloor: Double
    /// Eye aspect ratio (height / width) below which the eye reads as closed.
    public var closedEyeAspectRatio: Double
    /// Weight of the worst face in a group shot, so one badly blurred face is
    /// not averaged away.
    public var worstFaceWeight: Double
    public var croppedOrBlurredFacePenalty: Double
    public var closedEyesPenalty: Double

    // MARK: - Weights

    public var weightsWithoutFaces: Weights
    public var weightsWithFaces: Weights

    /// Favorite is a tie-break-sized nudge, never a way to outrank a defect.
    public var favoriteBonus: Double
    /// Hard ceiling of the resolution contribution to the final score.
    public var resolutionWeightCap: Double

    // MARK: - Confidence

    public var automaticSelectionMinimumScore: Double
    public var automaticSelectionMinimumMargin: Double
    public var lowConfidenceMinimumMargin: Double
    /// Score differences below this are treated as equal, so a rescan of an
    /// unchanged set cannot reorder candidates through floating-point noise.
    public var scoreEqualityTolerance: Double
    /// Value used for a component that could not be measured for one candidate
    /// while the rest of the cluster has it — neither a reward nor a penalty.
    public var neutralComponentScore: Double
    /// A component must lead by at least this much to be worth naming as the
    /// reason the winner won.
    public var reasonCodeMinimumDelta: Double

    public struct Weights: Codable, Sendable, Equatable {
        public var sharpness: Double
        public var faceQuality: Double
        public var exposure: Double
        public var noiseArtifacts: Double
        public var resolution: Double

        public init(
            sharpness: Double,
            faceQuality: Double,
            exposure: Double,
            noiseArtifacts: Double,
            resolution: Double
        ) {
            self.sharpness = sharpness
            self.faceQuality = faceQuality
            self.exposure = exposure
            self.noiseArtifacts = noiseArtifacts
            self.resolution = resolution
        }

        public var total: Double {
            sharpness + faceQuality + exposure + noiseArtifacts + resolution
        }
    }

    public init(
        scoringModelVersion: Int = 1,
        thumbnailConfigVersion: Int = 1,
        analysisImageLongSide: Int = 256,
        faceCropSide: Int = 256,
        minimumAnalysisLongSide: Int = 128,
        sharpnessGridSide: Int = 128,
        maxConcurrentAnalysisTasks: Int = 4,
        absoluteSharpnessFloor: Double = 10,
        criticalSharpnessRatio: Double = 0.55,
        strongPenaltySharpnessRatio: Double = 0.75,
        weakPenaltySharpnessRatio: Double = 0.90,
        referenceSharpnessRatio: Double = 0.90,
        criticalSharpnessPenalty: Double = 0.30,
        strongSharpnessPenalty: Double = 0.15,
        weakSharpnessPenalty: Double = 0.05,
        subjectSharpnessWeight: Double = 0.70,
        normalizationLowPercentile: Double = 0.10,
        normalizationHighPercentile: Double = 0.90,
        darkClippingLuma: Double = 5.0 / 255.0,
        brightClippingLuma: Double = 250.0 / 255.0,
        clippingFreeFraction: Double = 0.03,
        clippingFullPenaltyFraction: Double = 0.10,
        clippingCriticalFraction: Double = 0.15,
        lowContrastStdDev: Double = 0.06,
        lowContrastPenalty: Double = 0.10,
        minimumFaceDetectionConfidence: Double = 0.70,
        minimumFacePixelSize: Double = 64,
        blinkConfidenceFloor: Double = 0.80,
        closedEyeAspectRatio: Double = 0.18,
        worstFaceWeight: Double = 0.60,
        croppedOrBlurredFacePenalty: Double = 0.20,
        closedEyesPenalty: Double = 0.15,
        weightsWithoutFaces: Weights = Weights(
            sharpness: 0.55,
            faceQuality: 0,
            exposure: 0.25,
            noiseArtifacts: 0.15,
            resolution: 0.05
        ),
        weightsWithFaces: Weights = Weights(
            sharpness: 0.40,
            faceQuality: 0.25,
            exposure: 0.20,
            noiseArtifacts: 0.10,
            resolution: 0.05
        ),
        favoriteBonus: Double = 0.02,
        resolutionWeightCap: Double = 0.05,
        automaticSelectionMinimumScore: Double = 0.60,
        automaticSelectionMinimumMargin: Double = 0.08,
        lowConfidenceMinimumMargin: Double = 0.04,
        scoreEqualityTolerance: Double = 0.000_1,
        neutralComponentScore: Double = 0.50,
        reasonCodeMinimumDelta: Double = 0.01
    ) {
        self.scoringModelVersion = scoringModelVersion
        self.thumbnailConfigVersion = thumbnailConfigVersion
        self.analysisImageLongSide = analysisImageLongSide
        self.faceCropSide = faceCropSide
        self.minimumAnalysisLongSide = minimumAnalysisLongSide
        self.sharpnessGridSide = sharpnessGridSide
        self.maxConcurrentAnalysisTasks = maxConcurrentAnalysisTasks
        self.absoluteSharpnessFloor = absoluteSharpnessFloor
        self.criticalSharpnessRatio = criticalSharpnessRatio
        self.strongPenaltySharpnessRatio = strongPenaltySharpnessRatio
        self.weakPenaltySharpnessRatio = weakPenaltySharpnessRatio
        self.referenceSharpnessRatio = referenceSharpnessRatio
        self.criticalSharpnessPenalty = criticalSharpnessPenalty
        self.strongSharpnessPenalty = strongSharpnessPenalty
        self.weakSharpnessPenalty = weakSharpnessPenalty
        self.subjectSharpnessWeight = subjectSharpnessWeight
        self.normalizationLowPercentile = normalizationLowPercentile
        self.normalizationHighPercentile = normalizationHighPercentile
        self.darkClippingLuma = darkClippingLuma
        self.brightClippingLuma = brightClippingLuma
        self.clippingFreeFraction = clippingFreeFraction
        self.clippingFullPenaltyFraction = clippingFullPenaltyFraction
        self.clippingCriticalFraction = clippingCriticalFraction
        self.lowContrastStdDev = lowContrastStdDev
        self.lowContrastPenalty = lowContrastPenalty
        self.minimumFaceDetectionConfidence = minimumFaceDetectionConfidence
        self.minimumFacePixelSize = minimumFacePixelSize
        self.blinkConfidenceFloor = blinkConfidenceFloor
        self.closedEyeAspectRatio = closedEyeAspectRatio
        self.worstFaceWeight = worstFaceWeight
        self.croppedOrBlurredFacePenalty = croppedOrBlurredFacePenalty
        self.closedEyesPenalty = closedEyesPenalty
        self.weightsWithoutFaces = weightsWithoutFaces
        self.weightsWithFaces = weightsWithFaces
        self.favoriteBonus = favoriteBonus
        self.resolutionWeightCap = resolutionWeightCap
        self.automaticSelectionMinimumScore = automaticSelectionMinimumScore
        self.automaticSelectionMinimumMargin = automaticSelectionMinimumMargin
        self.lowConfidenceMinimumMargin = lowConfidenceMinimumMargin
        self.scoreEqualityTolerance = scoreEqualityTolerance
        self.neutralComponentScore = neutralComponentScore
        self.reasonCodeMinimumDelta = reasonCodeMinimumDelta
    }

    /// The configuration the app ships with.
    public static let current = PhotoQualityScoringConfig()

    /// Long side in points for the analysis image request.
    public var analysisTargetSize: (width: Int, height: Int) {
        (analysisImageLongSide, analysisImageLongSide)
    }
}
