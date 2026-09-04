import Core
import CoreGraphics
import Foundation
import Photos
import Vision
import XCTest
@testable import PhotoAnalysis

final class PhotoQualityAnalysisServiceTests: XCTestCase {
    private let service = PhotoQualityAnalysisService(faceDetector: { _ in [] })

    // MARK: - Raw signal ordering

    func testCheckerboardIsMeasuredSharperThanFlatGray() throws {
        let sharp = try XCTUnwrap(makeCheckerboardImage())
        let flat = try XCTUnwrap(makeFlatImage(level: 127))

        let sharpSignals = service.signals(for: sharp, pixelArea: 1_000)
        let flatSignals = service.signals(for: flat, pixelArea: 1_000)

        XCTAssertGreaterThan(sharpSignals.globalSharpness, flatSignals.globalSharpness)
        XCTAssertNil(sharpSignals.analysisFailure)
    }

    func testBlownOutFrameReportsBrightClipping() throws {
        let white = try XCTUnwrap(makeFlatImage(level: 255))

        let signals = service.signals(for: white, pixelArea: 1_000)

        XCTAssertGreaterThan(signals.brightClippedFraction, 0.9)
        XCTAssertEqual(signals.darkClippedFraction, 0, accuracy: 0.000_1)
    }

    func testCrushedFrameReportsDarkClipping() throws {
        let black = try XCTUnwrap(makeFlatImage(level: 0))

        let signals = service.signals(for: black, pixelArea: 1_000)

        XCTAssertGreaterThan(signals.darkClippedFraction, 0.9)
        XCTAssertEqual(signals.brightClippedFraction, 0, accuracy: 0.000_1)
    }

    func testFlatFrameReportsLowContrast() throws {
        let flat = try XCTUnwrap(makeFlatImage(level: 127))
        let contrasty = try XCTUnwrap(makeCheckerboardImage())

        let flatSignals = service.signals(for: flat, pixelArea: 1_000)
        let contrastySignals = service.signals(for: contrasty, pixelArea: 1_000)

        XCTAssertLessThan(flatSignals.subjectLumaStdDev, PhotoQualityScoringConfig.current.lowContrastStdDev)
        XCTAssertGreaterThan(contrastySignals.subjectLumaStdDev, flatSignals.subjectLumaStdDev)
    }

    func testNoisyFrameIsMeasuredNoisierThanCleanFrame() throws {
        let noisy = try XCTUnwrap(makeNoisyImage())
        let clean = try XCTUnwrap(makeFlatImage(level: 127))

        let noisySignals = service.signals(for: noisy, pixelArea: 1_000)
        let cleanSignals = service.signals(for: clean, pixelArea: 1_000)

        XCTAssertGreaterThan(noisySignals.noiseEstimate, cleanSignals.noiseEstimate)
    }

    func testTooSmallImageIsReportedAsFailureInsteadOfAScore() throws {
        let tiny = try XCTUnwrap(makeFlatImage(level: 127, side: 32))

        let signals = service.signals(for: tiny, pixelArea: 1_000)

        XCTAssertEqual(signals.analysisFailure, .tooSmallToAnalyze)
        XCTAssertFalse(signals.isUsable)
    }

    func testFaceDetectionFailureStillProducesUsableSignals() throws {
        struct DetectionError: Error {}
        let failing = PhotoQualityAnalysisService(faceDetector: { _ in throw DetectionError() })
        let image = try XCTUnwrap(makeCheckerboardImage())

        let signals = failing.signals(for: image, pixelArea: 1_000)

        XCTAssertTrue(signals.isUsable)
        XCTAssertFalse(signals.hasFaces)
    }

    /// The subject is the face that fills the frame, not the sharpest one: a
    /// small crisp bystander must not speak for a blurred person in front.
    func testTheLargestFaceProvidesTheSubjectSignals() throws {
        // Left half flat (the big, soft subject), right half a fine checkerboard
        // (the small, sharp bystander).
        let image = try XCTUnwrap(makeImage(side: 256, value: { x, _ in
            guard x >= 128 else { return 127 }
            return x.isMultiple(of: 2) ? 0 : 255
        }))
        let service = PhotoQualityAnalysisService(faceDetector: { _ in
            [
                // Vision boxes are normalized with a bottom-left origin.
                VNFaceObservation(boundingBox: CGRect(x: 0.05, y: 0.2, width: 0.4, height: 0.6)),
                VNFaceObservation(boundingBox: CGRect(x: 0.6, y: 0.4, width: 0.3, height: 0.3))
            ]
        })

        let signals = service.signals(for: image, pixelArea: 1_000)
        let subjectSharpness = try XCTUnwrap(signals.subjectSharpness)
        let sharpestFace = try XCTUnwrap(signals.usableFaceSignals.map(\.sharpness).max())

        XCTAssertEqual(signals.usableFaceSignals.count, 2)
        XCTAssertLessThan(subjectSharpness, sharpestFace)
    }

    // MARK: - The face size gate

    /// The bug this all exists for. A person occupying 8 % of the frame — a
    /// group shot, or anyone a couple of metres away — was rejected outright,
    /// because the gate demanded 64 pixels of a 256-pixel analysis image, which
    /// is a quarter of the long side. Given a face source with real pixels in
    /// it, that same face is now measured.
    func testAnOrdinaryDistantFaceIsMeasuredInsteadOfDiscarded() throws {
        let analysisImage = try XCTUnwrap(makeCheckerboardImage(side: 256))
        let faceSource = try XCTUnwrap(makeCheckerboardImage(side: 1_024))
        let service = PhotoQualityAnalysisService(faceDetector: { _ in
            [VNFaceObservation(boundingBox: Self.faceBox(fraction: 0.08))]
        })

        let signals = service.signals(
            for: analysisImage,
            faceSource: faceSource,
            pixelArea: 12_000_000
        )

        XCTAssertTrue(signals.hasFaces)
        XCTAssertEqual(signals.rejectedFaceCounts, .empty)
        XCTAssertNotNil(signals.subjectSharpness)
    }

    /// And it is measured on the face source's pixels, not on the handful the
    /// analysis thumbnail could offer.
    func testFaceSharpnessIsMeasuredOnTheFaceSourcePixels() throws {
        let analysisImage = try XCTUnwrap(makeCheckerboardImage(side: 256))
        let faceSource = try XCTUnwrap(makeCheckerboardImage(side: 1_024))
        let service = PhotoQualityAnalysisService(faceDetector: { _ in
            [VNFaceObservation(boundingBox: Self.faceBox(fraction: 0.08))]
        })

        let signals = service.signals(
            for: analysisImage,
            faceSource: faceSource,
            pixelArea: 12_000_000
        )
        let face = try XCTUnwrap(signals.usableFaceSignals.first)
        let sourcePixelSize = try XCTUnwrap(face.sourcePixelSize)

        XCTAssertGreaterThanOrEqual(
            sourcePixelSize,
            Double(PhotoQualityScoringConfig.current.faceCropSide)
        )
        // The box is still reported in analysis-image pixels, which is what
        // `boxPixelSize` has always meant.
        XCTAssertEqual(face.boxPixelSize, 0.08 * 256, accuracy: 1)
        XCTAssertLessThan(face.boxPixelSize, sourcePixelSize)
    }

    /// Without a face source there are only ~20 real pixels behind that face.
    /// Rather than stretch them onto the crop grid and call the result
    /// sharpness, the face is rejected — and the rejection is counted, so the
    /// photo does not look like one with nobody in it.
    func testAFaceWithoutEnoughRealPixelsIsRejectedAndCountedRatherThanInterpolated() throws {
        let analysisImage = try XCTUnwrap(makeCheckerboardImage(side: 256))
        let service = PhotoQualityAnalysisService(faceDetector: { _ in
            [VNFaceObservation(boundingBox: Self.faceBox(fraction: 0.08))]
        })

        let signals = service.signals(for: analysisImage, faceSource: nil, pixelArea: 12_000_000)

        XCTAssertFalse(signals.hasFaces)
        XCTAssertTrue(signals.hasOnlyRejectedFaces)
        XCTAssertEqual(signals.rejectedFaceCounts?.insufficientResolution, 1)
        XCTAssertEqual(signals.rejectedFaceCounts?.tooSmallInFrame, 0)
    }

    /// A face too small to be the subject is still turned away — the fraction
    /// gate is a relevance gate, not a removed one — but it is counted before
    /// the crop stage, so the reason is legible.
    func testAFaceTooSmallToBeTheSubjectIsCountedAgainstTheFrameFraction() throws {
        let analysisImage = try XCTUnwrap(makeCheckerboardImage(side: 256))
        let faceSource = try XCTUnwrap(makeCheckerboardImage(side: 1_024))
        let service = PhotoQualityAnalysisService(faceDetector: { _ in
            [VNFaceObservation(boundingBox: Self.faceBox(fraction: 0.01))]
        })

        let signals = service.signals(
            for: analysisImage,
            faceSource: faceSource,
            pixelArea: 12_000_000
        )

        XCTAssertFalse(signals.hasFaces)
        XCTAssertEqual(signals.rejectedFaceCounts?.tooSmallInFrame, 1)
        XCTAssertEqual(signals.rejectedFaceCounts?.insufficientResolution, 0)
    }

    /// A synthesized observation reports full confidence, so the floor is
    /// raised above it rather than faking a low-confidence detection.
    func testAFaceBelowTheConfidenceFloorIsCountedSeparately() throws {
        let analysisImage = try XCTUnwrap(makeCheckerboardImage(side: 256))
        var config = PhotoQualityScoringConfig.current
        config.minimumFaceDetectionConfidence = 2
        let service = PhotoQualityAnalysisService(config: config, faceDetector: { _ in
            [VNFaceObservation(boundingBox: Self.faceBox(fraction: 0.5))]
        })

        let signals = service.signals(for: analysisImage, faceSource: nil, pixelArea: 12_000_000)

        XCTAssertFalse(signals.hasFaces)
        XCTAssertTrue(signals.hasOnlyRejectedFaces)
        XCTAssertEqual(signals.rejectedFaceCounts?.lowConfidence, 1)
        XCTAssertEqual(signals.rejectedFaceCounts?.tooSmallInFrame, 0)
    }

    /// A detector that threw measured nothing, so it rejected nothing either.
    /// Reporting a rejection here would blame the gate for a Vision failure.
    func testADetectorFailureIsNotRecordedAsARejection() throws {
        struct DetectionError: Error {}
        let service = PhotoQualityAnalysisService(faceDetector: { _ in throw DetectionError() })
        let image = try XCTUnwrap(makeCheckerboardImage())

        let signals = service.signals(for: image, pixelArea: 1_000)

        XCTAssertEqual(signals.rejectedFaceCounts, .empty)
        XCTAssertFalse(signals.hasOnlyRejectedFaces)
    }

    /// A photo about to be recorded as `tooSmallToAnalyze` must not pay for
    /// face detection, nor for a second image request, before that verdict.
    func testAnImageTooSmallToAnalyzeIsNotProbedForFaces() async throws {
        let tiny = try XCTUnwrap(makeCheckerboardImage(side: 32))
        let requestedSides = RequestedSideRecorder()
        let detectorCalls = CallCounter()
        let service = PhotoQualityAnalysisService(
            imageProvider: { asset, size in
                await requestedSides.record(identifier: asset.localIdentifier, side: Int(size.width))
                return tiny
            },
            faceDetector: { _ in
                CallCounter.recordSynchronously(detectorCalls)
                return [VNFaceObservation(boundingBox: Self.faceBox(fraction: 0.5))]
            }
        )

        let scores = try await service.scores(for: [TestPHAsset(identifier: "tiny")])

        let sides = await requestedSides.sides(for: "tiny")

        XCTAssertEqual(scores.first?.signals.analysisFailure, .tooSmallToAnalyze)
        XCTAssertEqual(sides.count, 1)
        XCTAssertEqual(detectorCalls.count, 0)
    }

    /// Vision is not monotonic in resolution — this PR's own measurements show
    /// a group photo yielding 2 faces at 512 px and none at 768. So a
    /// re-detection that comes back with fewer faces must not be taken
    /// wholesale: the face it dropped was already accepted, and losing it takes
    /// the subject sharpness and the blink/crop penalties with it.
    func testAFaceTheReDetectionMissesIsKeptFromTheFirstPass() throws {
        let analysisImage = try XCTUnwrap(makeCheckerboardImage(side: 512))
        let faceSource = try XCTUnwrap(makeCheckerboardImage(side: 1_024))
        let left = Self.faceBox(fraction: 0.20, x: 0.05)
        let right = Self.faceBox(fraction: 0.20, x: 0.60)
        let service = PhotoQualityAnalysisService(faceDetector: { image in
            // The thumbnail sees both; the larger source sees only the left one.
            image.width == 512
                ? [VNFaceObservation(boundingBox: left), VNFaceObservation(boundingBox: right)]
                : [VNFaceObservation(boundingBox: left)]
        })

        let signals = service.signals(
            for: analysisImage,
            faceSource: faceSource,
            pixelArea: 12_000_000
        )

        XCTAssertEqual(signals.usableFaceSignals.count, 2, "the dropped face must survive the merge")
        // Both are measured on the face source, not one on each image.
        let sizes = signals.usableFaceSignals.compactMap(\.sourcePixelSize)
        XCTAssertEqual(sizes.count, 2)
        XCTAssertTrue(sizes.allSatisfy { $0 > 128 }, "expected face-source pixels, got \(sizes)")
    }

    /// The merge must not turn one person into two when both passes see them.
    func testAFaceBothPassesSeeIsCountedOnce() throws {
        let analysisImage = try XCTUnwrap(makeCheckerboardImage(side: 512))
        let faceSource = try XCTUnwrap(makeCheckerboardImage(side: 1_024))
        let box = Self.faceBox(fraction: 0.20, x: 0.05)
        let service = PhotoQualityAnalysisService(faceDetector: { image in
            // The same face, detected a shade differently at the two sizes.
            image.width == 512
                ? [VNFaceObservation(boundingBox: box)]
                : [VNFaceObservation(boundingBox: box.insetBy(dx: 0.005, dy: 0.005))]
        })

        let signals = service.signals(
            for: analysisImage,
            faceSource: faceSource,
            pixelArea: 12_000_000
        )

        XCTAssertEqual(signals.usableFaceSignals.count, 1)
    }

    // MARK: - The face source request

    func testTheFaceSourceIsRequestedOnlyForPhotosThatHaveAFace() async throws {
        let image = try XCTUnwrap(makeCheckerboardImage(side: 256))
        let requestedSides = RequestedSideRecorder()
        let service = PhotoQualityAnalysisService(
            imageProvider: { asset, size in
                await requestedSides.record(identifier: asset.localIdentifier, side: Int(size.width))
                return image
            },
            faceDetector: { _ in
                [VNFaceObservation(boundingBox: Self.faceBox(fraction: 0.08))]
            }
        )

        _ = try await service.scores(for: [TestPHAsset(identifier: "portrait")])
        let sides = await requestedSides.sides(for: "portrait")

        XCTAssertEqual(sides.first, PhotoQualityScoringConfig.current.analysisImageLongSide)
        XCTAssertEqual(sides.count, 2, "a photo with a face pays for a second, larger image")
        XCTAssertEqual(
            sides.last,
            PhotoQualityScoringConfig.current.faceSourceLongSide(smallestAcceptedFaceFraction: 0.08)
        )
    }

    func testAPhotoWithoutFacesCostsExactlyOneImageRequest() async throws {
        let image = try XCTUnwrap(makeCheckerboardImage(side: 256))
        let requestedSides = RequestedSideRecorder()
        let service = PhotoQualityAnalysisService(
            imageProvider: { asset, size in
                await requestedSides.record(identifier: asset.localIdentifier, side: Int(size.width))
                return image
            },
            faceDetector: { _ in [] }
        )

        _ = try await service.scores(for: [TestPHAsset(identifier: "landscape")])
        let sides = await requestedSides.sides(for: "landscape")

        XCTAssertEqual(sides, [PhotoQualityScoringConfig.current.analysisImageLongSide])
    }

    /// A second request that fails must not cost the photo its faces: they are
    /// measured on the analysis image instead, which is a degraded reading but
    /// an honest one.
    func testAFailedFaceSourceRequestFallsBackToTheAnalysisImage() async throws {
        let analysisImage = try XCTUnwrap(makeCheckerboardImage(side: 256))
        let service = PhotoQualityAnalysisService(
            imageProvider: { _, size in
                Int(size.width) == PhotoQualityScoringConfig.current.analysisImageLongSide
                    ? analysisImage
                    : nil
            },
            faceDetector: { _ in
                [VNFaceObservation(boundingBox: Self.faceBox(fraction: 0.30))]
            }
        )

        let scores = try await service.scores(for: [TestPHAsset(identifier: "portrait")])
        let signals = try XCTUnwrap(scores.first?.signals)

        XCTAssertTrue(signals.isUsable)
        // 30 % of a 256-pixel frame is 77 real pixels, above the crop side, so
        // the fallback still produces a measurement.
        XCTAssertTrue(signals.hasFaces)
    }

    private static func faceBox(fraction: Double, x: Double = 0.2) -> CGRect {
        // Vision boxes are normalized with a bottom-left origin; a square box
        // of this fraction has exactly `fraction` of the long side.
        CGRect(x: x, y: 0.2, width: fraction, height: fraction)
    }

    // MARK: - Batch behaviour

    func testBatchAnalysisStaysWithinTheConfiguredConcurrencyLimit() async throws {
        let tracker = AnalysisConcurrencyTracker()
        let image = try XCTUnwrap(makeCheckerboardImage())
        let service = PhotoQualityAnalysisService(
            imageProvider: { _, _ in
                await tracker.start()
                try? await Task.sleep(for: .milliseconds(20))
                await tracker.finish()
                return image
            },
            faceDetector: { _ in [] }
        )
        let assets = (0..<16).map { TestPHAsset(identifier: "asset-\($0)") }

        let scores = try await service.scores(for: assets)

        XCTAssertEqual(scores.count, assets.count)
        let maximumConcurrentCount = await tracker.maximumConcurrentCount
        XCTAssertLessThanOrEqual(
            maximumConcurrentCount,
            PhotoQualityScoringConfig.current.maxConcurrentAnalysisTasks
        )
    }

    func testBatchAnalysisPropagatesCancellation() async {
        let service = PhotoQualityAnalysisService(
            imageProvider: { _, _ in
                try await Task.sleep(for: .seconds(5))
                return nil
            },
            faceDetector: { _ in [] }
        )
        let assets = (0..<8).map { TestPHAsset(identifier: "asset-\($0)") }

        let task = Task { try await service.scores(for: assets) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOneUnreadablePhotoIsRecordedAsAFailureWithoutFailingTheBatch() async throws {
        let image = try XCTUnwrap(makeCheckerboardImage())
        let service = PhotoQualityAnalysisService(
            imageProvider: { asset, _ in
                asset.localIdentifier == "broken" ? nil : image
            },
            faceDetector: { _ in [] }
        )
        let assets = [
            TestPHAsset(identifier: "good"),
            TestPHAsset(identifier: "broken"),
            TestPHAsset(identifier: "also-good")
        ]

        let scores = try await service.scores(for: assets)
        let byIdentifier = Dictionary(uniqueKeysWithValues: scores.map { ($0.localIdentifier, $0) })

        XCTAssertEqual(scores.count, 3)
        XCTAssertEqual(byIdentifier["broken"]?.signals.analysisFailure, .assetUnavailable)
        XCTAssertEqual(byIdentifier["good"]?.signals.isUsable, true)
        XCTAssertEqual(byIdentifier["also-good"]?.signals.isUsable, true)
    }

    func testScoresCarryTheAssetIdentityAndConfigVersions() async throws {
        let image = try XCTUnwrap(makeCheckerboardImage())
        let service = PhotoQualityAnalysisService(
            imageProvider: { _, _ in image },
            faceDetector: { _ in [] }
        )
        let asset = TestPHAsset(identifier: "one", modificationDate: Date(timeIntervalSince1970: 77))

        let scores = try await service.scores(for: [asset])
        let score = try XCTUnwrap(scores.first)

        XCTAssertEqual(score.localIdentifier, "one")
        XCTAssertEqual(score.sourceModificationDate, Date(timeIntervalSince1970: 77))
        XCTAssertEqual(score.scoringModelVersion, PhotoQualityScoringConfig.current.scoringModelVersion)
        XCTAssertEqual(score.thumbnailConfigVersion, PhotoQualityScoringConfig.current.thumbnailConfigVersion)
        XCTAssertEqual(score.signals.pixelArea, 12_000_000)
        XCTAssertFalse(score.isAlikeEnhanced)
    }

    // MARK: - Helpers

    private func makeCheckerboardImage(side: Int = 256) -> CGImage? {
        makeImage(side: side) { x, y in (x / 4 + y / 4) % 2 == 0 ? 0 : 255 }
    }

    private func makeFlatImage(level: UInt8, side: Int = 256) -> CGImage? {
        makeImage(side: side) { _, _ in level }
    }

    private func makeNoisyImage(side: Int = 256) -> CGImage? {
        var generator = SystemRandomNumberGenerator()
        var values = [UInt8]()
        values.reserveCapacity(side * side)
        for _ in 0..<(side * side) {
            values.append(UInt8.random(in: 110...145, using: &generator))
        }
        return makeImage(side: side) { x, y in values[(y * side) + x] }
    }

    private func makeImage(side: Int, value: (Int, Int) -> UInt8) -> CGImage? {
        let bytesPerPixel = 4
        let bytesPerRow = side * bytesPerPixel
        var data = [UInt8](repeating: 0, count: side * side * bytesPerPixel)

        for y in 0..<side {
            for x in 0..<side {
                let index = (y * bytesPerRow) + (x * bytesPerPixel)
                let level = value(x, y)
                data[index] = level
                data[index + 1] = level
                data[index + 2] = level
                data[index + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

/// Counts detector invocations from a `@Sendable` closure.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    static func recordSynchronously(_ counter: CallCounter) {
        counter.lock.withLock { counter.value += 1 }
    }
}

/// Records the image sizes each asset was asked for, so the two-pass request
/// pattern can be asserted from the outside.
private actor RequestedSideRecorder {
    private var sidesByIdentifier: [String: [Int]] = [:]

    func record(identifier: String, side: Int) {
        sidesByIdentifier[identifier, default: []].append(side)
    }

    func sides(for identifier: String) -> [Int] {
        sidesByIdentifier[identifier] ?? []
    }
}

private actor AnalysisConcurrencyTracker {
    private var currentConcurrentCount = 0
    private(set) var maximumConcurrentCount = 0

    func start() {
        currentConcurrentCount += 1
        maximumConcurrentCount = max(maximumConcurrentCount, currentConcurrentCount)
    }

    func finish() {
        currentConcurrentCount -= 1
    }
}
