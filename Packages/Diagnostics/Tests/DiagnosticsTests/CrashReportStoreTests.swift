import XCTest
@testable import Diagnostics

final class CrashReportStoreTests: XCTestCase {
    private var directoryURL: URL!
    private var store: CrashReportStore!

    private var indexURL: URL { directoryURL.appendingPathComponent("index.json") }
    private var payloadsURL: URL { directoryURL.appendingPathComponent("payloads") }

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = CrashReportStore(directoryURL: directoryURL)
    }

    override func tearDownWithError() throws {
        store = nil
        if let directoryURL {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    private func payloadFileNames() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: payloadsURL.path)) ?? [])
    }

    private func writeIndex(_ json: String) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: indexURL)
    }

    // MARK: - Ingest

    func testMissingDirectoryReadsAsNoReports() async {
        let reports = await store.reports()
        XCTAssertEqual(reports, [])
    }

    func testIngestStoresThePayloadBytesUntouchedAndReadsItsMetadata() async throws {
        let payload = CrashPayloadFixture.data()
        let receivedAt = Date(timeIntervalSince1970: 1_790_000_000)

        await store.ingest([payload], receivedAt: receivedAt)

        let reports = await store.reports()
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(report.receivedAt, receivedAt)
        XCTAssertEqual(report.appVersion, "1.5.0")
        XCTAssertEqual(report.appBuild, "12")
        XCTAssertEqual(report.osVersion, "iPhone OS 18.6 (22G86)")
        XCTAssertEqual(report.deviceModel, "iPhone14,3")
        XCTAssertEqual(report.promptState, .pending)
        let fileURL = await store.payloadFileURL(for: report.id)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(fileURL)), payload)
    }

    func testPayloadThatIsNotJSONIsStillKept() async throws {
        let payload = Data("not-json".utf8)

        await store.ingest([payload], receivedAt: Date(timeIntervalSince1970: 10))

        let report = try await XCTUnwrapAsync(await store.reports().first)
        XCTAssertNil(report.appVersion)
        let fileURL = await store.payloadFileURL(for: report.id)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(fileURL)), payload)
    }

    func testIngestSignalsAChange() async {
        var changes = await store.changes().makeAsyncIterator()

        await store.ingest([CrashPayloadFixture.data()])

        await changes.next()
    }

    /// One observer going away must not silence the store: the screen that watches it
    /// is torn down and rebuilt inside a single process.
    func testAChangeStreamOpenedAfterAnotherOneWasCancelledStillReceivesChanges() async throws {
        let store = store!
        let first = Task { for await _ in await store.changes() {} }
        try await Task.sleep(for: .milliseconds(50))
        first.cancel()
        _ = await first.value

        var second = await store.changes().makeAsyncIterator()
        await store.ingest([CrashPayloadFixture.data()])

        let change: Void? = await second.next()
        XCTAssertNotNil(change)
    }

    func testEveryOpenObserverIsToldAboutAChange() async {
        var first = await store.changes().makeAsyncIterator()
        var second = await store.changes().makeAsyncIterator()

        await store.ingest([CrashPayloadFixture.data()])

        let firstChange: Void? = await first.next()
        let secondChange: Void? = await second.next()
        XCTAssertNotNil(firstChange)
        XCTAssertNotNil(secondChange)
    }

    // MARK: - Prompt state

    func testPromptStateSurvivesAReload() async throws {
        await store.ingest([CrashPayloadFixture.data()], receivedAt: Date(timeIntervalSince1970: 10))
        let id = try await XCTUnwrapAsync(await store.reports().first).id

        await store.setPromptState(.declined, for: id)

        let reloaded = await CrashReportStore(directoryURL: directoryURL).reports()
        XCTAssertEqual(reloaded.map(\.promptState), [.declined])
    }

    // MARK: - Rotation

    func testExactlyAtTheLimitNothingIsRotatedOut() async {
        let store = CrashReportStore(directoryURL: directoryURL, maxReports: 3)
        for second in 1...3 {
            await store.ingest(
                [CrashPayloadFixture.data(build: "\(second)")],
                receivedAt: Date(timeIntervalSince1970: TimeInterval(second))
            )
        }

        let reports = await store.reports()
        XCTAssertEqual(reports.map(\.appBuild), ["1", "2", "3"])
        XCTAssertEqual(payloadFileNames().count, 3)
    }

    func testOverTheLimitTheOldestReportAndItsFileAreRemoved() async {
        let store = CrashReportStore(directoryURL: directoryURL, maxReports: 3)
        for second in 1...4 {
            await store.ingest(
                [CrashPayloadFixture.data(build: "\(second)")],
                receivedAt: Date(timeIntervalSince1970: TimeInterval(second))
            )
        }

        let reports = await store.reports()
        XCTAssertEqual(reports.map(\.appBuild), ["2", "3", "4"])
        XCTAssertEqual(payloadFileNames(), Set(reports.map { "\($0.id.uuidString).json" }))
    }

    func testDefaultLimitKeepsTwentyReports() async {
        let payloads = (1...21).map { CrashPayloadFixture.data(build: "\($0)") }

        await store.ingest(payloads, receivedAt: Date(timeIntervalSince1970: 10))

        let reports = await store.reports()
        XCTAssertEqual(reports.count, 20)
        XCTAssertEqual(reports.first?.appBuild, "2")
        XCTAssertEqual(payloadFileNames().count, 20)
    }

    func testOrphanedPayloadFileIsSweptOnTheNextWrite() async throws {
        await store.ingest([CrashPayloadFixture.data()], receivedAt: Date(timeIntervalSince1970: 10))
        let orphan = payloadsURL.appendingPathComponent("\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: orphan)

        await store.ingest([CrashPayloadFixture.data()], receivedAt: Date(timeIntervalSince1970: 20))

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertEqual(payloadFileNames().count, 2)
    }

    // MARK: - Persisted shape

    /// The schema 1 index, byte for byte as the first build that shipped it writes it. If this stops decoding,
    /// installed users lose their stored crash reports.
    func testSchemaOneIndexStillDecodes() async throws {
        try writeIndex(
            """
            {"reports":[{"appBuild":"12","appVersion":"1.5.0","deviceModel":"iPhone14,3",\
            "id":"8F1B6C0A-5B0E-4C43-9E55-0C6E4E6D2A11","osVersion":"iPhone OS 18.6 (22G86)",\
            "promptState":"pending","receivedAt":"2026-09-19T08:00:00Z"}],"schemaVersion":1}
            """
        )

        let reports = await store.reports()

        XCTAssertEqual(
            reports,
            [
                CrashReport(
                    id: try XCTUnwrap(UUID(uuidString: "8F1B6C0A-5B0E-4C43-9E55-0C6E4E6D2A11")),
                    receivedAt: Date(timeIntervalSince1970: 1_789_804_800),
                    appVersion: "1.5.0",
                    appBuild: "12",
                    osVersion: "iPhone OS 18.6 (22G86)",
                    deviceModel: "iPhone14,3",
                    promptState: .pending
                )
            ]
        )
    }

    func testIndexRoundTripsThroughTheEncoder() throws {
        let index = CrashReportIndex(reports: [
            CrashReport(receivedAt: Date(timeIntervalSince1970: 10), appVersion: "1.5.0", promptState: .sent),
            CrashReport(receivedAt: Date(timeIntervalSince1970: 20))
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(CrashReportIndex.self, from: encoder.encode(index))

        XCTAssertEqual(decoded, index)
    }

    func testRecordWithOnlyTheRequiredKeysDecodesAndIsNeverPromptedAbout() async throws {
        try writeIndex(
            """
            {"reports":[{"id":"8F1B6C0A-5B0E-4C43-9E55-0C6E4E6D2A11",\
            "receivedAt":"2026-09-19T08:00:00Z"}],"schemaVersion":1}
            """
        )

        let report = try await XCTUnwrapAsync(await store.reports().first)

        XCTAssertNil(report.appVersion)
        XCTAssertEqual(report.promptState, .prompted)
    }

    func testUnknownPromptStateDegradesToPrompted() async throws {
        try writeIndex(
            """
            {"reports":[{"id":"8F1B6C0A-5B0E-4C43-9E55-0C6E4E6D2A11","promptState":"snoozed",\
            "receivedAt":"2026-09-19T08:00:00Z"}],"schemaVersion":1}
            """
        )

        let reports = await store.reports()

        XCTAssertEqual(reports.map(\.promptState), [.prompted])
    }

    func testNewerSchemaIsIgnoredAndLeftUntouched() async throws {
        let newer = #"{"reports":[],"schemaVersion":99,"shape":"unknown"}"#
        try writeIndex(newer)

        await store.ingest([CrashPayloadFixture.data()])
        let reports = await store.reports()

        XCTAssertEqual(reports, [])
        XCTAssertEqual(try String(contentsOf: indexURL, encoding: .utf8), newer)
        XCTAssertEqual(payloadFileNames(), [])
    }

    func testCorruptIndexIsRebuiltFromThePayloadFilesWithoutPromptingAgain() async throws {
        await store.ingest([CrashPayloadFixture.data()], receivedAt: Date(timeIntervalSince1970: 10))
        let original = try await XCTUnwrapAsync(await store.reports().first)
        try Data("{\"reports\":[{".utf8).write(to: indexURL)

        let rebuilt = await store.reports()

        XCTAssertEqual(rebuilt.map(\.id), [original.id])
        XCTAssertEqual(rebuilt.map(\.appVersion), ["1.5.0"])
        XCTAssertEqual(rebuilt.map(\.promptState), [.prompted])
    }

    func testIngestOverACorruptIndexKeepsTheRecoveredPayloads() async throws {
        await store.ingest([CrashPayloadFixture.data(build: "1")], receivedAt: Date(timeIntervalSince1970: 10))
        try Data("garbage".utf8).write(to: indexURL)

        await store.ingest([CrashPayloadFixture.data(build: "2")], receivedAt: Date())

        let reports = await store.reports()
        XCTAssertEqual(reports.map(\.appBuild), ["1", "2"])
        XCTAssertEqual(reports.map(\.promptState), [.prompted, .pending])
        XCTAssertEqual(payloadFileNames().count, 2)
    }
}

/// `XCTUnwrap` for a value produced by an `await`.
func XCTUnwrapAsync<T>(
    _ expression: @autoclosure () async throws -> T?,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws -> T {
    let value = try await expression()
    return try XCTUnwrap(value, file: file, line: line)
}
