import Foundation
import Testing
@testable import Diagnostics

@MainActor
@Suite struct CrashReportPromptCoordinatorTests {
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
    @Test func testObservingAgainAfterTheFirstObserverWasCancelledStillBumpsTheRevision() async throws {
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

        #expect(coordinator.revision > before)
    }

    @Test func testPendingReportIsPresentedOnACalmScreen() async {
        await store.ingest([CrashPayloadFixture.data()])

        await coordinator.evaluate(isBusy: { false })

        #expect(coordinator.presented?.reports.count == 1)
    }

    @Test func testBusyScreenPresentsNothingAndKeepsTheReportPending() async {
        await store.ingest([CrashPayloadFixture.data()])

        await coordinator.evaluate(isBusy: { true })

        #expect(coordinator.presented == nil)
        let states = await store.reports().map(\.promptState)
        #expect(states == [.pending])
    }

    @Test func testScreenClaimedWhileTheStoreWasReadPresentsNothing() async {
        await store.ingest([CrashPayloadFixture.data()])
        var reads = 0

        await coordinator.evaluate(isBusy: {
            reads += 1
            return reads > 1
        })

        #expect(coordinator.presented == nil)
    }

    @Test func testDecidingToPresentDoesNotSpendTheAsk() async {
        await store.ingest([CrashPayloadFixture.data()])

        await coordinator.evaluate(isBusy: { false })

        let states = await store.reports().map(\.promptState)
        #expect(states == [.pending])
    }

    @Test func testOnceTheSheetAppearedTheReportIsNeverAskedAboutAgain() async throws {
        await store.ingest([CrashPayloadFixture.data()])
        await coordinator.evaluate(isBusy: { false })
        let prompt = try #require(coordinator.presented)

        await coordinator.didPresent(prompt)

        let relaunched = CrashReportPromptCoordinator(store: CrashReportStore(directoryURL: directoryURL))
        await relaunched.evaluate(isBusy: { false })
        #expect(relaunched.presented == nil)
    }

    @Test func testDeclineIsFinalAndDismisses() async throws {
        await store.ingest([CrashPayloadFixture.data(), CrashPayloadFixture.data()])
        await coordinator.evaluate(isBusy: { false })
        let prompt = try #require(coordinator.presented)

        await coordinator.decline(prompt)
        await coordinator.evaluate(isBusy: { false })

        #expect(coordinator.presented == nil)
        let states = await store.reports().map(\.promptState)
        #expect(states == [.declined, .declined])
    }

    @Test func testSentIsRecordedAndDismisses() async throws {
        await store.ingest([CrashPayloadFixture.data()])
        await coordinator.evaluate(isBusy: { false })
        let prompt = try #require(coordinator.presented)

        await coordinator.markSent(prompt)

        #expect(coordinator.presented == nil)
        let states = await store.reports().map(\.promptState)
        #expect(states == [.sent])
    }

    @Test func testAttachmentsAreThePayloadFilesOfThePrompt() async throws {
        await store.ingest([CrashPayloadFixture.data()])
        await coordinator.evaluate(isBusy: { false })
        let prompt = try #require(coordinator.presented)

        let urls = await coordinator.attachmentURLs(for: prompt)

        #expect(urls.map(\.lastPathComponent) == ["\(prompt.id.uuidString).json"])
    }
}
