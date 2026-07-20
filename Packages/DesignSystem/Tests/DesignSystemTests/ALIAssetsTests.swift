import Foundation
import ImageIO
import XCTest
import Lottie
@testable import DesignSystem

final class ALIAssetsTests: XCTestCase {
    func testScannerIdleExportsAreAvailableForEveryStateAndScale() {
        let scales: [ALIAssets.ScannerIdleScale] = [.oneX, .twoX, .threeX]

        for state in ALIAssets.ScannerIdleState.allCases {
            for scale in scales {
                let url = ALIAssets.scannerIdleURL(for: state, scale: scale)
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            }
        }
    }

    func testScannerIdleOverlaysAreAvailableAndValid() throws {
        for state in ALIAssets.ScannerIdleState.allCases {
            let overlayURL = try XCTUnwrap(ALIAssets.scannerIdleOverlayURL(for: state))
            XCTAssertTrue(FileManager.default.fileExists(atPath: overlayURL.path))
            XCTAssertNotNil(LottieAnimation.filepath(overlayURL.path))
        }
    }

    func testWelcomeHeroExportsAreAvailable() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.welcomeHeroURL(for: .oneX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.welcomeHeroURL(for: .twoX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.welcomeHeroURL(for: .threeX).path))
    }

    func testWelcomeHeroOverlayIsAvailable() {
        let overlayURL = try? XCTUnwrap(ALIAssets.welcomeHeroOverlayURL)
        XCTAssertNotNil(overlayURL)
        XCTAssertTrue(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertNotNil(overlayURL.flatMap { LottieAnimation.filepath($0.path) })
    }

    func testScannerSearchingExportsAreAvailable() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.scannerSearchingURL(for: .oneX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.scannerSearchingURL(for: .twoX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.scannerSearchingURL(for: .threeX).path))
    }

    func testScannerSearchingOverlayIsAvailable() {
        let overlayURL = try? XCTUnwrap(ALIAssets.scannerSearchingOverlayURL)
        XCTAssertNotNil(overlayURL)
        XCTAssertTrue(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertNotNil(overlayURL.flatMap { LottieAnimation.filepath($0.path) })
    }

    func testComparisonReviewExportsAreAvailable() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.comparisonReviewURL(for: .oneX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.comparisonReviewURL(for: .twoX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.comparisonReviewURL(for: .threeX).path))
    }

    func testComparisonReviewOverlayIsAvailable() {
        let overlayURL = try? XCTUnwrap(ALIAssets.comparisonReviewOverlayURL)
        XCTAssertNotNil(overlayURL)
        XCTAssertTrue(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertNotNil(overlayURL.flatMap { LottieAnimation.filepath($0.path) })
    }

    func testBestShotExportsAreAvailable() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.bestShotURL(for: .oneX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.bestShotURL(for: .twoX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.bestShotURL(for: .threeX).path))
    }

    func testBestShotOverlayIsAvailable() {
        let overlayURL = try? XCTUnwrap(ALIAssets.bestShotOverlayURL)
        XCTAssertNotNil(overlayURL)
        XCTAssertTrue(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertNotNil(overlayURL.flatMap { LottieAnimation.filepath($0.path) })
    }

    func testCleanupProgressExportsAreDecodableAtExpectedSizes() throws {
        try assertRasterExports([
            (ALIAssets.cleanupProgressURL(for: .oneX), 418),
            (ALIAssets.cleanupProgressURL(for: .twoX), 836),
            (ALIAssets.cleanupProgressURL(for: .threeX), 1_254),
        ])
    }

    func testCleanupProgressOverlayIsAvailable() {
        let overlayURL = try? XCTUnwrap(ALIAssets.cleanupProgressOverlayURL)
        XCTAssertNotNil(overlayURL)
        XCTAssertTrue(overlayURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertNotNil(overlayURL.flatMap { LottieAnimation.filepath($0.path) })
    }

    func testCleanupSuccessExportsAreDecodableAtExpectedSizes() throws {
        try assertRasterExports([
            (ALIAssets.cleanupSuccessURL(for: .oneX), 418),
            (ALIAssets.cleanupSuccessURL(for: .twoX), 836),
            (ALIAssets.cleanupSuccessURL(for: .threeX), 1_254),
        ])
    }

    func testCleanupSuccessOverlayIsAvailable() {
        let overlayURL = try? XCTUnwrap(ALIAssets.cleanupSuccessOverlayURL)
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
