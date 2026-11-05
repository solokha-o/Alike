import Foundation
import ImageIO
import Testing
import Lottie
@testable import DesignSystem

@Suite struct AlikeAssetsTests {
    @Test func testScannerIdleExportsAreAvailableForEveryStateAndScale() {
        let scales: [AlikeAssets.ScannerIdleScale] = [.oneX, .twoX, .threeX]

        for state in AlikeAssets.ScannerIdleState.allCases {
            for scale in scales {
                let url = AlikeAssets.scannerIdleURL(for: state, scale: scale)
                #expect(FileManager.default.fileExists(atPath: url.path))
            }
        }
    }

    @Test func testScannerIdleOverlaysAreAvailableAndValid() throws {
        for state in AlikeAssets.ScannerIdleState.allCases {
            let overlayURL = try #require(AlikeAssets.scannerIdleOverlayURL(for: state))
            #expect(FileManager.default.fileExists(atPath: overlayURL.path))
            #expect(LottieAnimation.filepath(overlayURL.path) != nil)
        }
    }

    @Test func testWelcomeHeroExportsAreAvailable() {
        #expect(FileManager.default.fileExists(atPath: AlikeAssets.welcomeHeroURL(for: .oneX).path))
        #expect(FileManager.default.fileExists(atPath: AlikeAssets.welcomeHeroURL(for: .twoX).path))
        #expect(FileManager.default.fileExists(atPath: AlikeAssets.welcomeHeroURL(for: .threeX).path))
    }

    @Test func testWelcomeHeroOverlayIsAvailable() {
        let overlayURL = try? #require(AlikeAssets.welcomeHeroOverlayURL)
        #expect(overlayURL != nil)
        #expect(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        #expect(overlayURL.flatMap { LottieAnimation.filepath($0.path) } != nil)
    }

    @Test func testScannerSearchingExportsAreAvailable() {
        #expect(FileManager.default.fileExists(atPath: AlikeAssets.scannerSearchingURL(for: .oneX).path))
        #expect(FileManager.default.fileExists(atPath: AlikeAssets.scannerSearchingURL(for: .twoX).path))
        #expect(FileManager.default.fileExists(atPath: AlikeAssets.scannerSearchingURL(for: .threeX).path))
    }

    @Test func testScannerSearchingOverlayIsAvailable() {
        let overlayURL = try? #require(AlikeAssets.scannerSearchingOverlayURL)
        #expect(overlayURL != nil)
        #expect(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        #expect(overlayURL.flatMap { LottieAnimation.filepath($0.path) } != nil)
    }

    @Test func testScannerIssueExportsAreDecodableAtExpectedSizes() throws {
        try assertRasterExports([
            (AlikeAssets.scannerIssueURL(for: .oneX), 418),
            (AlikeAssets.scannerIssueURL(for: .twoX), 836),
            (AlikeAssets.scannerIssueURL(for: .threeX), 1_254),
        ])
    }

    @Test func testComparisonReviewExportsAreAvailable() {
        #expect(FileManager.default.fileExists(atPath: AlikeAssets.comparisonReviewURL(for: .oneX).path))
        #expect(FileManager.default.fileExists(atPath: AlikeAssets.comparisonReviewURL(for: .twoX).path))
        #expect(FileManager.default.fileExists(atPath: AlikeAssets.comparisonReviewURL(for: .threeX).path))
    }

    @Test func testComparisonReviewOverlayIsAvailable() {
        let overlayURL = try? #require(AlikeAssets.comparisonReviewOverlayURL)
        #expect(overlayURL != nil)
        #expect(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        #expect(overlayURL.flatMap { LottieAnimation.filepath($0.path) } != nil)
    }

    @Test func testBestShotExportsAreAvailable() {
        #expect(FileManager.default.fileExists(atPath: AlikeAssets.bestShotURL(for: .oneX).path))
        #expect(FileManager.default.fileExists(atPath: AlikeAssets.bestShotURL(for: .twoX).path))
        #expect(FileManager.default.fileExists(atPath: AlikeAssets.bestShotURL(for: .threeX).path))
    }

    @Test func testBestShotOverlayIsAvailable() {
        let overlayURL = try? #require(AlikeAssets.bestShotOverlayURL)
        #expect(overlayURL != nil)
        #expect(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        #expect(overlayURL.flatMap { LottieAnimation.filepath($0.path) } != nil)
    }

    @Test func testCleanupProgressExportsAreDecodableAtExpectedSizes() throws {
        try assertRasterExports([
            (AlikeAssets.cleanupProgressURL(for: .oneX), 418),
            (AlikeAssets.cleanupProgressURL(for: .twoX), 836),
            (AlikeAssets.cleanupProgressURL(for: .threeX), 1_254),
        ])
    }

    @Test func testCleanupProgressOverlayIsAvailable() {
        let overlayURL = try? #require(AlikeAssets.cleanupProgressOverlayURL)
        #expect(overlayURL != nil)
        #expect(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        #expect(overlayURL.flatMap { LottieAnimation.filepath($0.path) } != nil)
    }

    @Test func testCleanupSuccessExportsAreDecodableAtExpectedSizes() throws {
        try assertRasterExports([
            (AlikeAssets.cleanupSuccessURL(for: .oneX), 418),
            (AlikeAssets.cleanupSuccessURL(for: .twoX), 836),
            (AlikeAssets.cleanupSuccessURL(for: .threeX), 1_254),
        ])
    }

    @Test func testCleanupSuccessOverlayIsAvailable() {
        let overlayURL = try? #require(AlikeAssets.cleanupSuccessOverlayURL)
        #expect(overlayURL != nil)
        #expect(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        #expect(overlayURL.flatMap { LottieAnimation.filepath($0.path) } != nil)
    }

    private func assertRasterExports(
        _ exports: [(url: URL, expectedPixelSize: Int)],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        for export in exports {
            let source = try #require(
                CGImageSourceCreateWithURL(export.url as CFURL, nil),
                "Expected a decodable image source at \(export.url.lastPathComponent)",
                sourceLocation: sourceLocation
            )
            let image = try #require(
                CGImageSourceCreateImageAtIndex(source, 0, nil),
                "Expected a decodable image at \(export.url.lastPathComponent)",
                sourceLocation: sourceLocation
            )
            #expect(image.width == export.expectedPixelSize, sourceLocation: sourceLocation)
            #expect(image.height == export.expectedPixelSize, sourceLocation: sourceLocation)
        }
    }
}
