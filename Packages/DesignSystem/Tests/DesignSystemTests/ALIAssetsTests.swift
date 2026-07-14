import XCTest
@testable import DesignSystem

final class ALIAssetsTests: XCTestCase {
    func testWelcomeHeroExportsAreAvailable() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.welcomeHeroURL(for: .oneX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.welcomeHeroURL(for: .twoX).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.welcomeHeroURL(for: .threeX).path))
    }

    func testWelcomeHeroOverlayIsAvailable() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: ALIAssets.welcomeHeroOverlayURL.path))
    }
}
