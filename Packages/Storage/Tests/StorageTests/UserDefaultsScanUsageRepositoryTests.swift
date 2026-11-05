import Testing
import Foundation
@testable import Storage

/// A `final class` suite: each test gets its own `UserDefaults` suite, and `deinit`
/// removes it. The repository is an actor and `UserDefaults` is not `Sendable`, so
/// each repository gets its own `UserDefaults` instance of that suite.
@Suite final class UserDefaultsScanUsageRepositoryTests {
    private let suiteName = UUID().uuidString
    private let defaults: UserDefaults
    private let monthlyUsageKey: String
    private let legacyUsageKey: String
    private let calendar: Calendar

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        monthlyUsageKey = "premium.monthlyScanUsage.test.\(UUID().uuidString)"
        legacyUsageKey = "\(monthlyUsageKey).legacy"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func testMissingUsageLoadsAsNilAndCanBeInitialized() async {
        let repository = makeRepository()
        let date = makeDate(year: 2026, month: 7, day: 12)

        let missing = await repository.loadMonthlyUsage(at: date)
        #expect(missing == nil)

        let initial = usage(for: date, count: 1)
        await repository.initializeMonthlyUsage(initial)
        let loaded = await repository.loadMonthlyUsage(at: date)
        #expect(loaded == initial)
    }

    @Test func testRecordingSuccessfulScanIncrementsCurrentMonth() async {
        let repository = makeRepository()
        let date = makeDate(year: 2026, month: 7, day: 12)
        await repository.initializeMonthlyUsage(usage(for: date, count: 1))

        let updated = await repository.recordCompletedScan(at: date)

        #expect(updated.completedScanCount == 2)
        #expect(updated.remainingFreeScans == 1)
    }

    @Test func testLoadingAfterCalendarMonthBoundaryResetsAllowance() async {
        let repository = makeRepository()
        let july = makeDate(year: 2026, month: 7, day: 31)
        let august = makeDate(year: 2026, month: 8, day: 1)
        await repository.initializeMonthlyUsage(usage(for: july, count: 3))

        let reset = await repository.loadMonthlyUsage(at: august)

        #expect(reset?.completedScanCount == 0)
        #expect(reset?.remainingFreeScans == 3)
        #expect(reset?.periodStart == makeDate(year: 2026, month: 8, day: 1))
        #expect(reset?.nextResetDate == makeDate(year: 2026, month: 9, day: 1))
    }

    @Test func testFreshRepositoryObservesPersistedMonthReset() async {
        let july = makeDate(year: 2026, month: 7, day: 12)
        let august = makeDate(year: 2026, month: 8, day: 5)
        let firstRepository = makeRepository()
        await firstRepository.initializeMonthlyUsage(usage(for: july, count: 3))

        let relaunchedRepository = makeRepository()
        let reset = await relaunchedRepository.loadMonthlyUsage(at: august)

        #expect(reset?.completedScanCount == 0)
        #expect(reset?.remainingFreeScans == 3)
    }

    private func makeRepository() -> UserDefaultsScanUsageRepository {
        UserDefaultsScanUsageRepository(
            defaults: UserDefaults(suiteName: suiteName)!,
            monthlyUsageKey: monthlyUsageKey,
            legacyCompletedScanCountKey: legacyUsageKey,
            calendar: calendar
        )
    }

    private func usage(for date: Date, count: Int) -> MonthlyScanUsage {
        let components = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: components)!
        return MonthlyScanUsage(
            periodStart: start,
            nextResetDate: calendar.date(byAdding: .month, value: 1, to: start)!,
            completedScanCount: count
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
