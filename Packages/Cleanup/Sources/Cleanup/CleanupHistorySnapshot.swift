import Core
import Foundation

struct CleanupHistorySnapshot: Equatable, Sendable {
    let insights: CleanupInsights
    let sections: [CleanupHistorySection]

    init(entries: [CleanupCompletionRecord], calendar: Calendar = .current) {
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

    var isEmpty: Bool {
        sections.isEmpty
    }
}

struct CleanupHistorySection: Identifiable, Equatable, Sendable {
    let month: Date
    let entries: [CleanupCompletionRecord]

    var id: Date { month }
}

enum CleanupHistoryPhotoCount: Equatable, Sendable {
    case one
    case other(Int)

    init(_ count: Int) {
        self = count == 1 ? .one : .other(count)
    }
}
