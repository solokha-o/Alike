import Foundation
import XCTest
import Core
@testable import Settings

/// The reminder section shows the same schedule twice: the `Reminder schedule` row renders it
/// through `DateFormatter`, and the footer below describes the free schedule in prose. The footer
/// used to spell the time out — "Sunday at 6:00 PM" — which is only right for a reader on a
/// 12-hour clock. On a 24-hour device the row read `18:00` directly above a sentence saying
/// `6:00 PM`, in every language.
///
/// It now takes the formatted schedule as an argument, so this pins the shape (`%@`, no clock
/// time in any language) *and* exercises `CleanupReminderCopy` — the helper `SettingsView`
/// actually calls — against a fixed locale, calendar, and schedule. Reverting the production
/// formatting change, or wiring the wrong schedule into it, makes the exercised tests fail; the
/// catalog-shape tests alone would not have caught either.
final class ReminderScheduleCopyTests: XCTestCase {
    private static let footerKey = "settings.main.freeRemindersUseSundayAt"

    /// A digit followed by `:` or `.` and two more digits — `18:00`, `6:00`, `18.00`. Written this
    /// way rather than as a list of literals so a new locale cannot invent its own separator.
    private static let clockTime = try! NSRegularExpression(pattern: #"\d{1,2}[:.]\d{2}"#)

    func testTheFooterTakesTheFormattedScheduleInEveryLanguage() throws {
        let catalog = try LocalizationCatalog.load()

        for language in LocalizationCatalog.shippedLanguages {
            let value = try self.value(Self.footerKey, language, catalog)

            XCTAssertTrue(
                value.contains("%@"),
                "\(language) dropped the schedule argument: \(value)"
            )

            let range = NSRange(value.startIndex..., in: value)
            XCTAssertNil(
                Self.clockTime.firstMatch(in: value, range: range),
                "\(language) writes a clock time into the copy instead of using %@: \(value)"
            )
        }
    }

    /// The weekday is part of the formatted argument too — spelling it out would be wrong the
    /// moment the default schedule moves off Sunday, and it is the kind of thing a translation
    /// pass reintroduces without noticing.
    func testTheFooterCarriesExactlyOneArgument() throws {
        let catalog = try LocalizationCatalog.load()

        for language in LocalizationCatalog.shippedLanguages {
            let value = try self.value(Self.footerKey, language, catalog)
            let specifiers = value.components(separatedBy: "%@").count - 1

            XCTAssertEqual(specifiers, 1, "\(language) has \(specifiers) arguments: \(value)")
        }
    }

    /// `scheduleDescription` backs the "Reminder schedule" row, which renders whatever schedule is
    /// actually bound — not a fixed default. A build that ignored its `schedule` argument (or
    /// hardcoded `.defaultWeekly`) would still pass the catalog-shape tests above; this one fails
    /// because the output is compared against a `DateFormatter` run over the *same* schedule.
    func testScheduleDescriptionRendersTheGivenScheduleInA12HourLocale() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "en")
        let locale = Locale(identifier: "en_US")
        let calendar = fixedCalendar(locale: locale)
        let schedule = CleanupReminderSchedule(weekday: 3, hour: 9, minute: 5)

        let expectedTime = expectedTimeString(hour: 9, minute: 5, calendar: calendar, locale: locale)
        let expectedWeekday = expectedWeekdaySymbol(schedule.weekday, calendar: calendar, locale: locale)

        let result = CleanupReminderCopy.scheduleDescription(
            schedule,
            calendar: calendar,
            locale: locale,
            bundle: bundle
        )

        XCTAssertTrue(expectedTime.contains("AM") || expectedTime.contains("PM"), "en_US should be 12-hour: \(expectedTime)")
        XCTAssertEqual(result, "\(expectedWeekday) at \(expectedTime)")
    }

    /// Same helper, a 24-hour locale, and a different schedule again — proving the row does not
    /// quietly depend on the 12-hour formatting the footer used to hardcode.
    func testScheduleDescriptionRendersTheGivenScheduleInA24HourLocale() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "de")
        let locale = Locale(identifier: "de_DE")
        let calendar = fixedCalendar(locale: locale)
        let schedule = CleanupReminderSchedule(weekday: 5, hour: 18, minute: 0)

        let expectedTime = expectedTimeString(hour: 18, minute: 0, calendar: calendar, locale: locale)

        XCTAssertFalse(expectedTime.contains("PM"), "de_DE should be 24-hour: \(expectedTime)")
        XCTAssertNotNil(
            Self.clockTime.firstMatch(in: expectedTime, range: NSRange(expectedTime.startIndex..., in: expectedTime)),
            "expected a 24-hour clock string, got: \(expectedTime)"
        )

        let result = CleanupReminderCopy.scheduleDescription(
            schedule,
            calendar: calendar,
            locale: locale,
            bundle: bundle
        )

        XCTAssertTrue(result.contains(expectedTime), "\(result) does not contain the formatted 24-hour time \(expectedTime)")
    }

    /// The regression itself: the free-tier footer embeds `scheduleDescription(.defaultWeekly)`
    /// rather than a literal, so it tracks whatever 12/24-hour convention the row above used.
    /// Reverting to a hardcoded "6:00 PM" would still pass the plain string comparison here only
    /// by accident in a 12-hour locale — the 24-hour case below is what actually pins it.
    func testFooterEmbedsTheFormattedDefaultScheduleInA12HourLocale() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "en")
        let locale = Locale(identifier: "en_US")
        let calendar = fixedCalendar(locale: locale)

        let expectedSchedule = CleanupReminderCopy.scheduleDescription(
            .defaultWeekly,
            calendar: calendar,
            locale: locale,
            bundle: bundle
        )

        let footer = CleanupReminderCopy.footerText(
            hasPremiumAccess: false,
            calendar: calendar,
            locale: locale,
            bundle: bundle
        )

        XCTAssertTrue(footer.contains(expectedSchedule), "\(footer) does not contain \(expectedSchedule)")
    }

    func testFooterEmbedsTheFormattedDefaultScheduleInA24HourLocale() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "de")
        let locale = Locale(identifier: "de_DE")
        let calendar = fixedCalendar(locale: locale)

        let expectedSchedule = CleanupReminderCopy.scheduleDescription(
            .defaultWeekly,
            calendar: calendar,
            locale: locale,
            bundle: bundle
        )

        let footer = CleanupReminderCopy.footerText(
            hasPremiumAccess: false,
            calendar: calendar,
            locale: locale,
            bundle: bundle
        )

        XCTAssertFalse(footer.contains("PM"), "de_DE footer should not carry a 12-hour marker: \(footer)")
        XCTAssertTrue(footer.contains(expectedSchedule), "\(footer) does not contain \(expectedSchedule)")
        XCTAssertTrue(footer.contains("18:00"), "de_DE default schedule (18:00) missing from: \(footer)")
    }

    /// Premium copy is static — it never mentions a schedule, so it must not run the formatter at
    /// all.
    func testFooterIgnoresTheScheduleWhenPremiumIsUnlocked() throws {
        let bundle = try CompiledCatalogFixture.bundle(language: "en")
        let locale = Locale(identifier: "en_US")
        let calendar = fixedCalendar(locale: locale)

        let footer = CleanupReminderCopy.footerText(
            hasPremiumAccess: true,
            calendar: calendar,
            locale: locale,
            bundle: bundle
        )

        XCTAssertEqual(footer, "Premium lets you choose a custom weekly reminder schedule.")
    }

    private func value(
        _ key: String,
        _ language: String,
        _ catalog: LocalizationCatalog
    ) throws -> String {
        let localization = try XCTUnwrap(
            catalog.localizations(of: key)[language],
            "\(key) is missing \(language)"
        )
        let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String)
    }

    /// UTC keeps the formatted time independent of the day the date happens to fall on — no DST
    /// edge cases — while still exercising the locale's real 12/24-hour convention.
    private func fixedCalendar(locale: Locale) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func expectedTimeString(hour: Int, minute: Int, calendar: Calendar, locale: Locale) -> String {
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        components.hour = hour
        components.minute = minute
        let date = calendar.date(from: components) ?? Date()

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func expectedWeekdaySymbol(_ weekday: Int, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        let symbols = formatter.standaloneWeekdaySymbols ?? formatter.weekdaySymbols ?? []
        let index = max(1, min(weekday, symbols.count)) - 1
        return symbols.isEmpty ? "" : symbols[index]
    }
}
