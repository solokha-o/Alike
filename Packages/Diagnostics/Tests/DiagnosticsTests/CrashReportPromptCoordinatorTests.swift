import XCTest
@testable import Diagnostics

@MainActor
final class CrashReportPromptCoordinatorTests: XCTestCase {
    private var directoryURL: URL!
    private var store: CrashReportStore!
    private var coordinator: CrashReportPromptCoordinator!

    override func setUp() async throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = CrashReportStore(directoryURL: directoryURL)
        coordinator = CrashReportPromptCoordinator(store: store)
    }

    override func tearDown() async throws {
        coordinator = nil
        store = nil
        try? FileManager.default.removeItem(at: directoryURL)
    }

    /// "Delete all data" tears down the tab that observes the store and onboarding puts
    /// a new one back in the same process. The second observer has to keep working.
    func testObservingAgainAfterTheFirstObserverWasCancelledStillBumpsTheRevision() async throws {
        let firstObserver = Task { await coordinator.observeStore() }
        try await Task.sleep(for: .milliseconds(50))
        firstObserver.cancel()
        _ = await firstObserver.value

        let secondObserver = Task { await coordinator.observeStore() }
        try await Task.sleep(for: .milliseconds(50))
        let before = coordinator.revision
        await store.ingest([CrashPayloadFixture.data()])
        try await Task.sleep(for: .milliseconds(200))
        secondObserver.cancel()

        XCTAssertGreaterThan(coordinator.revision, before)
    }

    func testPendingReportIsPresentedOnACalmScreen() async {
        await store.ingest([CrashPayloadFixture.data()])

        await coordinator.evaluate(isBusy: { false })

        XCTAssertEqual(coordinator.presented?.reports.count, 1)
    }

    func testBusyScreenPresentsNothingAndKeepsTheReportPending() async {
        await store.ingest([CrashPayloadFixture.data()])

        await coordinator.evaluate(isBusy: { true })

        XCTAssertNil(coordinator.presented)
        let states = await store.reports().map(\.promptState)
        XCTAssertEqual(states, [.pending])
    }

    func testScreenClaimedWhileTheStoreWasReadPresentsNothing() async {
        await store.ingest([CrashPayloadFixture.data()])
        var reads = 0

        await coordinator.evaluate(isBusy: {
            reads += 1
            return reads > 1
        })

        XCTAssertNil(coordinator.presented)
    }

    func testDecidingToPresentDoesNotSpendTheAsk() async {
        await store.ingest([CrashPayloadFixture.data()])

        await coordinator.evaluate(isBusy: { false })

        let states = await store.reports().map(\.promptState)
        XCTAssertEqual(states, [.pending])
    }

    func testOnceTheSheetAppearedTheReportIsNeverAskedAboutAgain() async throws {
        await store.ingest([CrashPayloadFixture.data()])
        await coordinator.evaluate(isBusy: { false })
        let prompt = try XCTUnwrap(coordinator.presented)

        await coordinator.didPresent(prompt)

        let relaunched = CrashReportPromptCoordinator(store: CrashReportStore(directoryURL: directoryURL))
        await relaunched.evaluate(isBusy: { false })
        XCTAssertNil(relaunched.presented)
    }

    func testDeclineIsFinalAndDismisses() async throws {
        await store.ingest([CrashPayloadFixture.data(), CrashPayloadFixture.data()])
        await coordinator.evaluate(isBusy: { false })
        let prompt = try XCTUnwrap(coordinator.presented)

        await coordinator.decline(prompt)
        await coordinator.evaluate(isBusy: { false })

        XCTAssertNil(coordinator.presented)
        let states = await store.reports().map(\.promptState)
        XCTAssertEqual(states, [.declined, .declined])
    }

    func testSentIsRecordedAndDismisses() async throws {
        await store.ingest([CrashPayloadFixture.data()])
        await coordinator.evaluate(isBusy: { false })
        let prompt = try XCTUnwrap(coordinator.presented)

        await coordinator.markSent(prompt)

        XCTAssertNil(coordinator.presented)
        let states = await store.reports().map(\.promptState)
        XCTAssertEqual(states, [.sent])
    }

    func testAttachmentsAreThePayloadFilesOfThePrompt() async throws {
        await store.ingest([CrashPayloadFixture.data()])
        await coordinator.evaluate(isBusy: { false })
        let prompt = try XCTUnwrap(coordinator.presented)

        let urls = await coordinator.attachmentURLs(for: prompt)

        XCTAssertEqual(urls.map(\.lastPathComponent), ["\(prompt.id.uuidString).json"])
    }
}
