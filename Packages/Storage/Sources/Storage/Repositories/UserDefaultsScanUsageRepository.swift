import Foundation
import Core

/// UserDefaults-backed installation-local scan usage counter.
public actor UserDefaultsScanUsageRepository: ScanUsageRepository {
    private let defaults: UserDefaults
    private let monthlyUsageKey: String
    private let legacyCompletedScanCountKey: String
    private let calendar: Calendar

    public init(
        defaults: UserDefaults = .standard,
        monthlyUsageKey: String = "premium.monthlyScanUsage.v2",
        legacyCompletedScanCountKey: String = "premium.completedScanCount.v1",
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.defaults = defaults
        self.monthlyUsageKey = monthlyUsageKey
        self.legacyCompletedScanCountKey = legacyCompletedScanCountKey
        self.calendar = calendar
    }

    public func loadMonthlyUsage(at date: Date) -> MonthlyScanUsage? {
        let currentPeriod = makeUsage(at: date, completedScanCount: 0)
        if
            let data = defaults.data(forKey: monthlyUsageKey),
            let stored = try? JSONDecoder().decode(MonthlyScanUsage.self, from: data)
        {
            guard calendar.isDate(stored.periodStart, equalTo: currentPeriod.periodStart, toGranularity: .month) else {
                save(currentPeriod)
                return currentPeriod
            }
            return stored
        }

        guard defaults.object(forKey: legacyCompletedScanCountKey) != nil else { return nil }
        let migrated = makeUsage(
            at: date,
            completedScanCount: min(
                PremiumAccessPolicy.monthlyFreeScanLimit,
                max(0, defaults.integer(forKey: legacyCompletedScanCountKey))
            )
        )
        save(migrated)
        return migrated
    }

    public func initializeMonthlyUsage(_ usage: MonthlyScanUsage) {
        guard defaults.object(forKey: monthlyUsageKey) == nil else { return }
        save(usage)
    }

    public func recordCompletedScan(at date: Date) -> MonthlyScanUsage {
        let current = loadMonthlyUsage(at: date) ?? makeUsage(at: date, completedScanCount: 0)
        let updated = MonthlyScanUsage(
            periodStart: current.periodStart,
            nextResetDate: current.nextResetDate,
            completedScanCount: current.completedScanCount + 1
        )
        save(updated)
        return updated
    }

    private func makeUsage(at date: Date, completedScanCount: Int) -> MonthlyScanUsage {
        let components = calendar.dateComponents([.year, .month], from: date)
        let periodStart = calendar.date(from: components) ?? date
        let nextResetDate = calendar.date(byAdding: .month, value: 1, to: periodStart) ?? date
        return MonthlyScanUsage(
            periodStart: periodStart,
            nextResetDate: nextResetDate,
            completedScanCount: completedScanCount
        )
    }

    private func save(_ usage: MonthlyScanUsage) {
        if let data = try? JSONEncoder().encode(usage) {
            defaults.set(data, forKey: monthlyUsageKey)
        }
    }
}
