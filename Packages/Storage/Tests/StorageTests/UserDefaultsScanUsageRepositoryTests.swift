import XCTest
import Foundation
@testable import Storage

final class UserDefaultsScanUsageRepositoryTests: XCTestCase {
    private var monthlyUsageKey: String!
    private var legacyUsageKey: String!
    private var calendar: Calendar!

    override func setUp() {
        monthlyUsageKey = "premium.monthlyScanUsage.test.\(UUID().uuidString)"
        legacyUsageKey = "\(monthlyUsageKey!).legacy"
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: monthlyUsageKey)
        UserDefaults.standard.removeObject(forKey: legacyUsageKey)
        monthlyUsageKey = nil
        legacyUsageKey = nil
        calendar = nil
    }

    func testMissingUsageLoadsAsNilAndCanBeInitialized() async {
        let repository = makeRepository()
        let date = makeDate(year: 2026, month: 7, day: 12)

        let missing = await repository.loadMonthlyUsage(at: date)
        XCTAssertNil(missing)

        let initial = usage(for: date, count: 1)
        await repository.initializeMonthlyUsage(initial)
        let loaded = await repository.loadMonthlyUsage(at: date)
        XCTAssertEqual(loaded, initial)
    }

    func testRecordingSuccessfulScanIncrementsCurrentMonth() async {
        let repository = makeRepository()
        let date = makeDate(year: 2026, month: 7, day: 12)
        await repository.initializeMonthlyUsage(usage(for: date, count: 1))

        let updated = await repository.recordCompletedScan(at: date)

        XCTAssertEqual(updated.completedScanCount, 2)
        XCTAssertEqual(updated.remainingFreeScans, 1)
    }

    func testLoadingAfterCalendarMonthBoundaryResetsAllowance() async {
        let repository = makeRepository()
        let july = makeDate(year: 2026, month: 7, day: 31)
        let august = makeDate(year: 2026, month: 8, day: 1)
        await repository.initializeMonthlyUsage(usage(for: july, count: 3))

        let reset = await repository.loadMonthlyUsage(at: august)

        XCTAssertEqual(reset?.completedScanCount, 0)
        XCTAssertEqual(reset?.remainingFreeScans, 3)
        XCTAssertEqual(reset?.periodStart, makeDate(year: 2026, month: 8, day: 1))
        XCTAssertEqual(reset?.nextResetDate, makeDate(year: 2026, month: 9, day: 1))
    }

    func testFreshRepositoryObservesPersistedMonthReset() async {
        let july = makeDate(year: 2026, month: 7, day: 12)
        let august = makeDate(year: 2026, month: 8, day: 5)
        let firstRepository = makeRepository()
        await firstRepository.initializeMonthlyUsage(usage(for: july, count: 3))

        let relaunchedRepository = makeRepository()
        let reset = await relaunchedRepository.loadMonthlyUsage(at: august)

        XCTAssertEqual(reset?.completedScanCount, 0)
        XCTAssertEqual(reset?.remainingFreeScans, 3)
    }

    private func makeRepository() -> UserDefaultsScanUsageRepository {
        UserDefaultsScanUsageRepository(
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
