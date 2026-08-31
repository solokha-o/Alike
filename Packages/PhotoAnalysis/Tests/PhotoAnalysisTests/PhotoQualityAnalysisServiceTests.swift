import Core
import CoreGraphics
import Foundation
import Photos
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
