import Core
import XCTest
@testable import Cleanup

final class CleanupHistorySnapshotTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    func testEmptyHistoryProducesEmptyInsightsAndSections() {
        let snapshot = CleanupHistorySnapshot(entries: [], calendar: calendar)

        XCTAssertEqual(snapshot.insights, .empty)
        XCTAssertTrue(snapshot.sections.isEmpty)
        XCTAssertTrue(snapshot.isEmpty)
    }

    func testSnapshotAggregatesAndGroupsNewestFirst() {
        let januaryRecord = makeRecord(
            id: "00000000-0000-0000-0000-000000000001",
            count: 2,
            bytes: 1_024,
            year: 2025,
            month: 1,
            day: 31
        )
        let earlyFebruaryRecord = makeRecord(
            id: "00000000-0000-0000-0000-000000000002",
            count: 3,
            bytes: 2_048,
            year: 2025,
            month: 2,
            day: 1
        )
        let latestRecord = makeRecord(
            id: "00000000-0000-0000-0000-000000000003",
            count: 4,
            bytes: 4_096,
            year: 2025,
            month: 2,
            day: 15
        )

        let snapshot = CleanupHistorySnapshot(
            entries: [earlyFebruaryRecord, januaryRecord, latestRecord],
            calendar: calendar
        )

        XCTAssertEqual(snapshot.insights.totalDeletedItems, 9)
        XCTAssertEqual(snapshot.insights.totalSavedBytes, 7_168)
        XCTAssertEqual(snapshot.insights.cleanupSessionCount, 3)
        XCTAssertEqual(snapshot.insights.latestCleanup, latestRecord)
        XCTAssertEqual(snapshot.sections.count, 2)
        XCTAssertEqual(snapshot.sections[0].month, date(year: 2025, month: 2, day: 1))
        XCTAssertEqual(snapshot.sections[0].entries, [latestRecord, earlyFebruaryRecord])
        XCTAssertEqual(snapshot.sections[1].month, date(year: 2025, month: 1, day: 1))
        XCTAssertEqual(snapshot.sections[1].entries, [januaryRecord])
        XCTAssertFalse(snapshot.isEmpty)
    }

    func testSnapshotKeepsZeroByteRecordAndUsesItAsLatestCleanup() {
        let record = makeRecord(
            id: "00000000-0000-0000-0000-000000000004",
            count: 1,
            bytes: 0,
            year: 2025,
            month: 3,
            day: 1
        )

        let snapshot = CleanupHistorySnapshot(entries: [record], calendar: calendar)

        XCTAssertEqual(snapshot.insights.totalSavedBytes, 0)
        XCTAssertEqual(snapshot.insights.latestCleanup, record)
        XCTAssertEqual(snapshot.sections.first?.entries, [record])
    }

    func testPhotoCountDistinguishesSingularFromOtherCounts() {
        XCTAssertEqual(CleanupHistoryPhotoCount(1), .one)
        XCTAssertEqual(CleanupHistoryPhotoCount(0), .other(0))
        XCTAssertEqual(CleanupHistoryPhotoCount(2), .other(2))
    }

    private func makeRecord(
        id: String,
        count: Int,
        bytes: Int64,
        year: Int,
        month: Int,
        day: Int
    ) -> CleanupCompletionRecord {
        CleanupCompletionRecord(
            id: UUID(uuidString: id)!,
            sourceClusterID: UUID(),
            deletedCount: count,
            estimatedSavingsBytes: bytes,
            completedAt: date(year: year, month: month, day: day)
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
