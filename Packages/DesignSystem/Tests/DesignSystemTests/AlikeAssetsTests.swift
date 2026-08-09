import Foundation
import ImageIO
import XCTest
import Lottie
@testable import DesignSystem

final class AlikeAssetsTests: XCTestCase {
    func testScannerIdleExportsAreAvailableForEveryStateAndScale() {
        let scales: [AlikeAssets.ScannerIdleScale] = [.oneX, .twoX, .threeX]

        for state in AlikeAssets.ScannerIdleState.allCases {
            for scale in scales {
                let url = AlikeAssets.scannerIdleURL(for: state, scale: scale)
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            }
        }
    }

    func testScannerIdleOverlaysAreAvailableAndValid() throws {
        for state in AlikeAssets.ScannerIdleState.allCases {
            let overlayURL = try XCTUnwrap(AlikeAssets.scannerIdleOverlayURL(for: state))
            XCTAssertTrue(FileManager.default.fileExists(atPath: overlayURL.path))
            XCTAssertNotNil(LottieAnimation.filepath(overlayURL.path))
        }
    }

    func testWelcomeHeroExportsAreAvailable() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: AlikeAssets.welcomeHeroURL(for: .oneX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: AlikeAssets.welcomeHeroURL(for: .twoX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: AlikeAssets.welcomeHeroURL(for: .threeX).path))
    }

    func testWelcomeHeroOverlayIsAvailable() {
        let overlayURL = try? XCTUnwrap(AlikeAssets.welcomeHeroOverlayURL)
        XCTAssertNotNil(overlayURL)
        XCTAssertTrue(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertNotNil(overlayURL.flatMap { LottieAnimation.filepath($0.path) })
    }

    func testScannerSearchingExportsAreAvailable() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: AlikeAssets.scannerSearchingURL(for: .oneX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: AlikeAssets.scannerSearchingURL(for: .twoX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: AlikeAssets.scannerSearchingURL(for: .threeX).path))
    }

    func testScannerSearchingOverlayIsAvailable() {
        let overlayURL = try? XCTUnwrap(AlikeAssets.scannerSearchingOverlayURL)
        XCTAssertNotNil(overlayURL)
        XCTAssertTrue(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertNotNil(overlayURL.flatMap { LottieAnimation.filepath($0.path) })
    }

    func testScannerIssueExportsAreDecodableAtExpectedSizes() throws {
        try assertRasterExports([
            (AlikeAssets.scannerIssueURL(for: .oneX), 418),
            (AlikeAssets.scannerIssueURL(for: .twoX), 836),
            (AlikeAssets.scannerIssueURL(for: .threeX), 1_254),
        ])
    }

    func testComparisonReviewExportsAreAvailable() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: AlikeAssets.comparisonReviewURL(for: .oneX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: AlikeAssets.comparisonReviewURL(for: .twoX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: AlikeAssets.comparisonReviewURL(for: .threeX).path))
    }

    func testComparisonReviewOverlayIsAvailable() {
        let overlayURL = try? XCTUnwrap(AlikeAssets.comparisonReviewOverlayURL)
        XCTAssertNotNil(overlayURL)
        XCTAssertTrue(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertNotNil(overlayURL.flatMap { LottieAnimation.filepath($0.path) })
    }

    func testBestShotExportsAreAvailable() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: AlikeAssets.bestShotURL(for: .oneX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: AlikeAssets.bestShotURL(for: .twoX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: AlikeAssets.bestShotURL(for: .threeX).path))
    }

    func testBestShotOverlayIsAvailable() {
        let overlayURL = try? XCTUnwrap(AlikeAssets.bestShotOverlayURL)
        XCTAssertNotNil(overlayURL)
        XCTAssertTrue(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertNotNil(overlayURL.flatMap { LottieAnimation.filepath($0.path) })
    }

    func testCleanupProgressExportsAreDecodableAtExpectedSizes() throws {
        try assertRasterExports([
            (AlikeAssets.cleanupProgressURL(for: .oneX), 418),
            (AlikeAssets.cleanupProgressURL(for: .twoX), 836),
            (AlikeAssets.cleanupProgressURL(for: .threeX), 1_254),
        ])
    }

    func testCleanupProgressOverlayIsAvailable() {
        let overlayURL = try? XCTUnwrap(AlikeAssets.cleanupProgressOverlayURL)
        XCTAssertNotNil(overlayURL)
        XCTAssertTrue(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertNotNil(overlayURL.flatMap { LottieAnimation.filepath($0.path) })
    }

    func testCleanupSuccessExportsAreDecodableAtExpectedSizes() throws {
        try assertRasterExports([
            (AlikeAssets.cleanupSuccessURL(for: .oneX), 418),
            (AlikeAssets.cleanupSuccessURL(for: .twoX), 836),
            (AlikeAssets.cleanupSuccessURL(for: .threeX), 1_254),
        ])
    }

    func testCleanupSuccessOverlayIsAvailable() {
        let overlayURL = try? XCTUnwrap(AlikeAssets.cleanupSuccessOverlayURL)
        XCTAssertNotNil(overlayURL)
        XCTAssertTrue(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertNotNil(overlayURL.flatMap { LottieAnimation.filepath($0.path) })
    }

    private func assertRasterExports(
        _ exports: [(url: URL, expectedPixelSize: Int)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for export in exports {
            let source = try XCTUnwrap(
                CGImageSourceCreateWithURL(export.url as CFURL, nil),
                "Expected a decodable image source at \(export.url.lastPathComponent)",
                file: file,
                line: line
            )
            let image = try XCTUnwrap(
                CGImageSourceCreateImageAtIndex(source, 0, nil),
                "Expected a decodable image at \(export.url.lastPathComponent)",
                file: file,
                line: line
            )
            XCTAssertEqual(image.width, export.expectedPixelSize, file: file, line: line)
            XCTAssertEqual(image.height, export.expectedPixelSize, file: file, line: line)
        }
    }
}
