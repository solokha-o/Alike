import Cleanup
import Core
import XCTest

/// What a widget tap means once it reaches a workspace whose contents may have moved on
/// since the snapshot the widget was drawn from. The view that acts on this has no test
/// action worth the name, so the decision is made here.
final class CleanupWidgetEntryTests: XCTestCase {
    private func summary(_ kind: CleanupCategoryKind, assetCount: Int = 5) -> CleanupCategorySummary {
        CleanupCategorySummary(kind: kind, assetCount: assetCount, estimatedSavingsBytes: 1_000)
    }

    // MARK: - Categories

    /// The whole point of routing through a summary: the same value an in-app tap
    /// carries, so it reaches the same `openCategory` and therefore the same gate.
    func testACategoryResolvesToTheSummaryTheInAppTapWouldCarry() {
        let screenshots = summary(.screenshots)
        let entry = CleanupWidgetEntry.category(.screenshots)

        let resolution = entry.resolution(
            categories: [screenshots, summary(.blurredPhotos)],
            orderedClusterIDs: ["a"]
        )

        XCTAssertEqual(resolution, .openCategory(screenshots))
    }

    func testEachCategoryResolvesToItsOwnSummary() {
        let categories = [summary(.screenshots, assetCount: 86), summary(.blurredPhotos, assetCount: 12)]

        for kind in CleanupCategoryKind.allCases {
            let resolution = CleanupWidgetEntry.category(kind)
                .resolution(categories: categories, orderedClusterIDs: [])
            XCTAssertEqual(resolution, .openCategory(categories.first { $0.kind == kind }!))
        }
    }

    /// The widget's figures can be a day old. A category the app no longer has candidates
    /// for lands on the parent screen rather than on an empty sheet — and, for a free
    /// account, rather than on a paywall selling an empty list.
    func testACategoryTheWorkspaceNoLongerHasStaysOnTheRoot() {
        let resolution = CleanupWidgetEntry.category(.screenshots)
            .resolution(categories: [summary(.blurredPhotos)], orderedClusterIDs: ["a"])

        XCTAssertEqual(resolution, .stayOnRoot)
    }

    func testAnEmptyWorkspaceStaysOnTheRootForEveryCategory() {
        for kind in CleanupCategoryKind.allCases {
            let resolution = CleanupWidgetEntry.category(kind)
                .resolution(categories: [], orderedClusterIDs: [])
            XCTAssertEqual(resolution, .stayOnRoot, "\(kind) resolved to something with no data behind it")
        }
    }

    /// Resolution does not consult entitlement, and must not: a locked category has to
    /// resolve to its summary so that `CleanupView.openCategory` is the thing that turns
    /// it into a paywall. Deciding "locked, so stay on the root" here would silently
    /// swallow the tap instead.
    func testResolutionDoesNotDecideAccessItself() {
        let screenshots = summary(.screenshots)

        XCTAssertEqual(
            CleanupWidgetEntry.category(.screenshots)
                .resolution(categories: [screenshots], orderedClusterIDs: []),
            .openCategory(screenshots)
        )
    }

    // MARK: - Similar photos

    /// Clusters are sections on the cleanup root, not a screen of their own, so the row
    /// lands on the root with the first cluster brought into view.
    func testSimilarPhotosScrollsToTheFirstClusterInTheDisplayedOrder() {
        let resolution = CleanupWidgetEntry.similarPhotos
            .resolution(categories: [], orderedClusterIDs: ["needs-review-1", "remaining-1"])

        XCTAssertEqual(resolution, .scrollTo("needs-review-1"))
    }

    func testSimilarPhotosWithNoClustersStaysOnTheRoot() {
        let resolution = CleanupWidgetEntry.similarPhotos
            .resolution(categories: [summary(.screenshots)], orderedClusterIDs: [])

        XCTAssertEqual(resolution, .stayOnRoot)
    }
}
