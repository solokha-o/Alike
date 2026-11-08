import Core
import Foundation
import Testing
@testable import CleanupWorkspace

struct CleanupHistorySnapshotTests {
    private let calendar: Calendar

    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
    }

    @Test func testEmptyHistoryProducesEmptyInsightsAndSections() {
        let snapshot = CleanupHistorySnapshot(entries: [], calendar: calendar)

        #expect(snapshot.insights == .empty)
        #expect(snapshot.sections.isEmpty)
        #expect(snapshot.isEmpty)
    }

    @Test func testSnapshotAggregatesAndGroupsNewestFirst() {
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

        #expect(snapshot.insights.totalDeletedItems == 9)
        #expect(snapshot.insights.totalSavedBytes == 7_168)
        #expect(snapshot.insights.cleanupSessionCount == 3)
        #expect(snapshot.insights.latestCleanup == latestRecord)
        #expect(snapshot.sections.count == 2)
        #expect(snapshot.sections[0].month == date(year: 2025, month: 2, day: 1))
        #expect(snapshot.sections[0].entries == [latestRecord, earlyFebruaryRecord])
        #expect(snapshot.sections[1].month == date(year: 2025, month: 1, day: 1))
        #expect(snapshot.sections[1].entries == [januaryRecord])
        #expect(!snapshot.isEmpty)
    }

    @Test func testSnapshotKeepsZeroByteRecordAndUsesItAsLatestCleanup() {
        let record = makeRecord(
            id: "00000000-0000-0000-0000-000000000004",
            count: 1,
            bytes: 0,
            year: 2025,
            month: 3,
            day: 1
        )

        let snapshot = CleanupHistorySnapshot(entries: [record], calendar: calendar)

        #expect(snapshot.insights.totalSavedBytes == 0)
        #expect(snapshot.insights.latestCleanup == record)
        #expect(snapshot.sections.first?.entries == [record])
    }

    /// The months are cut on the calendar the header is spelled in, not on the device's.
    ///
    /// `CleanupHistoryView` renders each section header with `.alikePinned`, which is Gregorian
    /// everywhere. Grouping used to default to `Calendar.current`, so on an `ar-SA` device the
    /// buckets followed Umm al-Qura months while their labels stayed Gregorian, and an entry
    /// could sit under a header naming a month it did not happen in.
    @Test func testMonthsAreCutOnTheCalendarTheHeaderIsSpelledIn() throws {
        let groupingCalendar = CleanupHistorySnapshot.groupingCalendar
        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.locale = Locale(identifier: "ar_SA")
        hijri.timeZone = groupingCalendar.timeZone

        // Two days inside one Gregorian month that Umm al-Qura puts in different months. A
        // Gregorian month is long enough to always straddle such a boundary; finding it rather
        // than hard-coding it keeps the test honest if the Hijri tables are ever revised.
        let firstOfMarch = date(year: 2026, month: 3, day: 1, calendar: groupingCalendar)
        let hijriMonthOfFirst = hijri.component(.month, from: firstOfMarch)
        let secondDay = try #require((2...31).first { day in
                guard let candidate = groupingCalendar.date(
                    from: DateComponents(year: 2026, month: 3, day: day)
                ) else {
                    return false
                }
                return hijri.component(.month, from: candidate) != hijriMonthOfFirst
            }, "March 2026 does not straddle an Umm al-Qura month boundary")

        let earlier = makeRecord(
            id: "00000000-0000-0000-0000-000000000005",
            count: 1,
            bytes: 512,
            year: 2026,
            month: 3,
            day: 1,
            calendar: groupingCalendar
        )
        let later = makeRecord(
            id: "00000000-0000-0000-0000-000000000006",
            count: 1,
            bytes: 512,
            year: 2026,
            month: 3,
            day: secondDay,
            calendar: groupingCalendar
        )

        // Asserted directly as well as through the grouping: this machine's calendar is
        // Gregorian, so a revert to `.current` here would change nothing observable in the
        // sections below and would only surface on an Arabic device.
        #expect(groupingCalendar == Calendar.alikeFormattingCalendar)

        // The default initializer is the one the app uses.
        let snapshot = CleanupHistorySnapshot(entries: [earlier, later])

        #expect(snapshot.sections.count == 1)
        #expect(snapshot.sections.first?.entries == [later, earlier])
        for section in snapshot.sections {
            for entry in section.entries {
                #expect(header(of: section) == label(for: entry.completedAt), "an entry sits under a header naming another month")
            }
        }

        // What the old default did on an ar-SA device: the same two entries split across two
        // sections, and one of them headed with a month it did not happen in.
        let asTheDeviceCalendarWouldCutIt = CleanupHistorySnapshot(entries: [earlier, later], calendar: hijri)
        #expect(asTheDeviceCalendarWouldCutIt.sections.count == 2)
        let mislabelled = asTheDeviceCalendarWouldCutIt.sections.contains { section in
            section.entries.contains { entry in header(of: section) != label(for: entry.completedAt) }
        }
        #expect(mislabelled, Comment(rawValue: "expected the Hijri grouping to mislabel a section; headers: "
                + asTheDeviceCalendarWouldCutIt.sections.map { header(of: $0) }.joined(separator: ", ")))
    }

    /// The header `CleanupHistoryView` puts on a section.
    private func header(of section: CleanupHistorySection) -> String {
        label(for: section.month)
    }

    private func label(for date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().alikePinned)
    }

    private func makeRecord(
        id: String,
        count: Int,
        bytes: Int64,
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar? = nil
    ) -> CleanupCompletionRecord {
        CleanupCompletionRecord(
            id: UUID(uuidString: id)!,
            sourceClusterID: UUID(),
            deletedCount: count,
            estimatedSavingsBytes: bytes,
            completedAt: date(year: year, month: month, day: day, calendar: calendar)
        )
    }

    private func date(year: Int, month: Int, day: Int, calendar: Calendar? = nil) -> Date {
        (calendar ?? self.calendar).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
