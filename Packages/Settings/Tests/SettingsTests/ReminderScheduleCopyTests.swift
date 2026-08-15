import Foundation
import XCTest

/// The reminder section shows the same schedule twice: the `Reminder schedule` row renders it
/// through `DateFormatter`, and the footer below describes the free schedule in prose. The footer
/// used to spell the time out — "Sunday at 6:00 PM" — which is only right for a reader on a
/// 12-hour clock. On a 24-hour device the row read `18:00` directly above a sentence saying
/// `6:00 PM`, in every language.
///
/// It now takes the formatted schedule as an argument, so this pins the shape: the footer carries
/// a `%@` and no locale writes a clock time back into it.
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
}
