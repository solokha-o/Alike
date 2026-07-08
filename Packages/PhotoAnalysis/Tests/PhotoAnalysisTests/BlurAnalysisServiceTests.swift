import CoreGraphics
import XCTest
@testable import PhotoAnalysis

final class BlurAnalysisServiceTests: XCTestCase {
    func testBlurCandidateSelectorExcludesSharpItemsAndSortsResults() {
        let selected = BlurCandidateSelector.selectCandidates(from: [
            BlurAnalysisCandidate(localIdentifier: "sharp", sharpnessScore: 45, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "blur-small", sharpnessScore: 8, estimatedCleanupBytes: 200),
            BlurAnalysisCandidate(localIdentifier: "blur-large", sharpnessScore: 8, estimatedCleanupBytes: 500),
            BlurAnalysisCandidate(localIdentifier: "soft", sharpnessScore: 17, estimatedCleanupBytes: 300),
            BlurAnalysisCandidate(localIdentifier: "borderline", sharpnessScore: 19, estimatedCleanupBytes: 400),
            BlurAnalysisCandidate(localIdentifier: "sharp-2", sharpnessScore: 60, estimatedCleanupBytes: 250),
            BlurAnalysisCandidate(localIdentifier: "sharp-3", sharpnessScore: 80, estimatedCleanupBytes: 250),
            BlurAnalysisCandidate(localIdentifier: "sharp-4", sharpnessScore: 72, estimatedCleanupBytes: 240),
            BlurAnalysisCandidate(localIdentifier: "sharp-5", sharpnessScore: 65, estimatedCleanupBytes: 230),
            BlurAnalysisCandidate(localIdentifier: "sharp-6", sharpnessScore: 54, estimatedCleanupBytes: 220),
            BlurAnalysisCandidate(localIdentifier: "sharp-7", sharpnessScore: 51, estimatedCleanupBytes: 210),
            BlurAnalysisCandidate(localIdentifier: "sharp-8", sharpnessScore: 49, estimatedCleanupBytes: 205)
        ])

        XCTAssertEqual(selected.map(\.localIdentifier), ["blur-large"])
    }

    func testBlurCandidateSelectorReturnsEmptyForSmallPopulation() {
        let selected = BlurCandidateSelector.selectCandidates(from: [
            BlurAnalysisCandidate(localIdentifier: "one", sharpnessScore: 4, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "two", sharpnessScore: 5, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "three", sharpnessScore: 6, estimatedCleanupBytes: 100)
        ])

        XCTAssertTrue(selected.isEmpty)
    }

    func testBlurCandidateSelectorReturnsEmptyWhenAllPhotosAreReasonablySharp() {
        let selected = BlurCandidateSelector.selectCandidates(from: [
            BlurAnalysisCandidate(localIdentifier: "1", sharpnessScore: 21, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "2", sharpnessScore: 22, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "3", sharpnessScore: 23, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "4", sharpnessScore: 24, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "5", sharpnessScore: 25, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "6", sharpnessScore: 26, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "7", sharpnessScore: 27, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "8", sharpnessScore: 28, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "9", sharpnessScore: 29, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "10", sharpnessScore: 30, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "11", sharpnessScore: 31, estimatedCleanupBytes: 100),
            BlurAnalysisCandidate(localIdentifier: "12", sharpnessScore: 32, estimatedCleanupBytes: 100)
        ])

        XCTAssertTrue(selected.isEmpty)
    }

    func testBlurSharpnessScorerScoresBlurredImageLowerThanSharpImage() throws {
        let scorer = BlurSharpnessScorer()
        let sharp = try XCTUnwrap(makeStripedImage())
        let blurred = try XCTUnwrap(makeFlatImage())

        let sharpScore = scorer.score(image: sharp)
        let blurredScore = scorer.score(image: blurred)

        XCTAssertGreaterThan(sharpScore, blurredScore)
    }

    private func makeStripedImage() -> CGImage? {
        let width = 64
        let height = 64
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * bytesPerRow) + (x * bytesPerPixel)
                let value: UInt8 = (x / 4) % 2 == 0 ? 0 : 255
                data[index] = value
                data[index + 1] = value
                data[index + 2] = value
                data[index + 3] = 255
            }
        }

        return makeImage(from: data, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    private func makeFlatImage() -> CGImage? {
        let width = 64
        let height = 64
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let data = [UInt8](repeating: 127, count: width * height * bytesPerPixel)
        return makeImage(from: data, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    private func makeImage(from data: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(data) as CFData) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
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
