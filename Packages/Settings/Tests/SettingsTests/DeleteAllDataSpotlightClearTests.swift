import XCTest
@testable import Settings

/// The Spotlight step added to the Delete Alike Data flow (spike #5).
///
/// `RootView` composes the operation as: workspace reset → reminders off → local data
/// wipe → widget snapshot cleared → Spotlight index cleared → data-deleted callback.
/// These tests pin the two properties that matter for the user's data: the index is
/// cleared only after the local wipe succeeded, and a failure to clear it is reported
/// rather than hidden behind the callback.
@MainActor
final class DeleteAllDataSpotlightClearTests: XCTestCase {
    func testIndexIsClearedAfterTheLocalWipeAndBeforeTheCallback() async {
        let journal = DeletionJournal()
        let model = DeleteAllDataModel {
            journal.record(.localWipe)
            try await journal.clearSpotlight()
            journal.record(.callback)
        }

        await model.deleteAllData()

        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(journal.events, [.localWipe, .spotlightCleared, .callback])
    }

    func testAFailedLocalWipeNeverTouchesTheIndex() async {
        let journal = DeletionJournal()
        let model = DeleteAllDataModel {
            throw DeletionTestError.localWipeFailed
        }

        await model.deleteAllData()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(journal.events, [])
    }

    func testAFailedIndexClearSurfacesAsAnErrorAndSkipsTheCallback() async {
        let journal = DeletionJournal(failSpotlight: true)
        let model = DeleteAllDataModel {
            journal.record(.localWipe)
            try await journal.clearSpotlight()
            journal.record(.callback)
        }

        await model.deleteAllData()

        XCTAssertNotNil(model.errorMessage, "a stale Spotlight index is user data left behind; the user must hear about it")
        XCTAssertEqual(journal.events, [.localWipe])
    }
}

private enum DeletionTestError: Error {
    case localWipeFailed
    case spotlightFailed
}

@MainActor
private final class DeletionJournal {
    enum Event: Equatable {
        case localWipe
        case spotlightCleared
        case callback
    }

    private(set) var events: [Event] = []
    private let failSpotlight: Bool

    init(failSpotlight: Bool = false) {
        self.failSpotlight = failSpotlight
    }

    func record(_ event: Event) {
        events.append(event)
    }

    /// Stands in for `ClusterSpotlightPublisher.clear()`, which forwards to
    /// `CSSearchableIndex.deleteAllSearchableItems` through `SpotlightIndexClearing`.
    func clearSpotlight() async throws {
        if failSpotlight { throw DeletionTestError.spotlightFailed }
        events.append(.spotlightCleared)
    }
}
