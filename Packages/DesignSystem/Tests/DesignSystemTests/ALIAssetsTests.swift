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
}
