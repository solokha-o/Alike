import Core
import Foundation

public struct CleanupHistorySnapshot: Equatable, Sendable {
    public let insights: CleanupInsights
    public let sections: [CleanupHistorySection]

    /// The calendar the history is cut into months on.
    ///
    /// The pinned Gregorian one, not `.current`, because `CleanupHistoryView` spells the section
    /// header with `.alikePinned`: under `ar-SA` the device calendar is Umm al-Qura, so grouping
    /// by `.current` cut the entries on Hijri months and then labelled each bucket with the
    /// Gregorian month its first day happened to fall in — an entry under a header naming a
    /// month it did not happen in. Named rather than inlined so a test can assert the default
    /// on any device, including the Latin-digit ones where reverting it looks harmless.
    public static var groupingCalendar: Calendar { .alikeFormattingCalendar }

    public init(entries: [CleanupCompletionRecord], calendar: Calendar = CleanupHistorySnapshot.groupingCalendar) {
        let sortedEntries = entries.sorted { lhs, rhs in
            if lhs.completedAt == rhs.completedAt {
                return lhs.id.uuidString > rhs.id.uuidString
            }
            return lhs.completedAt > rhs.completedAt
        }

        insights = CleanupInsights(
            totalDeletedItems: sortedEntries.reduce(0) { $0 + $1.deletedCount },
            totalSavedBytes: sortedEntries.reduce(Int64(0)) { $0 + $1.estimatedSavingsBytes },
            cleanupSessionCount: sortedEntries.count,
            latestCleanup: sortedEntries.first
        )

        var entriesByMonth: [Date: [CleanupCompletionRecord]] = [:]
        for entry in sortedEntries {
            let components = calendar.dateComponents([.era, .year, .month], from: entry.completedAt)
            let month = calendar.date(from: components) ?? calendar.startOfDay(for: entry.completedAt)
            entriesByMonth[month, default: []].append(entry)
        }

        sections = entriesByMonth.keys
            .sorted(by: >)
            .map { month in
                CleanupHistorySection(month: month, entries: entriesByMonth[month, default: []])
            }
    }

    public var isEmpty: Bool {
        sections.isEmpty
    }
}

public struct CleanupHistorySection: Identifiable, Equatable, Sendable {
    public let month: Date
    public let entries: [CleanupCompletionRecord]

    public var id: Date { month }
}
