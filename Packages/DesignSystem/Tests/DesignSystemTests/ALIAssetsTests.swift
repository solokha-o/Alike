import XCTest
import Lottie
@testable import DesignSystem

final class ALIAssetsTests: XCTestCase {
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
}
