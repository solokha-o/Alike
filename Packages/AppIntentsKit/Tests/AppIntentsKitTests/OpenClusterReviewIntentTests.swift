import XCTest
@testable import AppIntentsKit

@MainActor
final class OpenClusterReviewIntentTests: XCTestCase {
    private let environment = TestEnvironment.shared

    override func setUp() {
        super.setUp()
        environment.reset()
    }

    func testEveryCategoryOpensItsOwnDestination() async throws {
        for category in ClusterReviewCategory.allCases {
            environment.reset(isPro: true)
            _ = try await OpenClusterReviewIntent.forTest(category: category).perform()
            XCTAssertEqual(environment.opened, [category.destination], "\(category)")
        }
        XCTAssertEqual(
            ClusterReviewCategory.allCases.map(\.destination),
            [.similarPhotos, .resumeReview, .screenshots, .blurredPhotos]
        )
    }

    func testProCategoryWithoutProReturnsThePaywallDialogAndStillHandsOverTheLink() async throws {
        for category in ClusterReviewCategory.allCases where category.requiresPro {
            environment.reset(isPro: false)

            let result = try await OpenClusterReviewIntent.forTest(category: category).perform()

            XCTAssertTrue(result.dialogText.contains(AppIntentsL10n.OpenReview.needsPro), result.dialogText)
            // The link is still handed over: `CleanupView.openCategory` owns the paywall,
            // and the intent must not become a second gate.
            XCTAssertEqual(environment.opened, [category.destination], "\(category)")
        }
    }

    func testProCategoryWithProOpensNormally() async throws {
        environment.reset(isPro: true)

        let result = try await OpenClusterReviewIntent.forTest(category: .screenshots).perform()

        XCTAssertTrue(result.dialogText.contains(AppIntentsL10n.OpenReview.opening), result.dialogText)
        XCTAssertEqual(environment.opened, [.screenshots])
    }

    func testFreeCategoriesNeverMentionPro() async throws {
        for category in ClusterReviewCategory.allCases where !category.requiresPro {
            environment.reset(isPro: false)
            let result = try await OpenClusterReviewIntent.forTest(category: category).perform()
            XCTAssertTrue(result.dialogText.contains(AppIntentsL10n.OpenReview.opening), result.dialogText)
        }
    }

    func testOnlyScreenshotsAndBlurredPhotosArePremium() {
        XCTAssertEqual(
            ClusterReviewCategory.allCases.filter(\.requiresPro),
            [.screenshots, .blurredPhotos]
        )
    }
}
