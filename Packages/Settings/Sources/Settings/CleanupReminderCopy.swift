import Foundation
import Core

/// Formatting for the cleanup reminder schedule and its free-tier footer, pulled out of
/// `SettingsView` so it can be exercised with a fixed locale/calendar instead of only through
/// live `Calendar.current` / `Locale.current` device state.
enum CleanupReminderCopy {
    /// The weekday + time sentence shown in the "Reminder schedule" row.
    static func scheduleDescription(
        _ schedule: CleanupReminderSchedule,
        calendar: Calendar,
        locale: Locale,
        bundle: Bundle? = nil
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        // `DateFormatter.timeZone` does not follow `calendar` automatically — leaving it unset
        // would format the schedule in the device's system time zone instead of the calendar
        // passed in, which only happened to agree with `.current` before this was injectable.
        formatter.timeZone = calendar.timeZone
        let weekdaySymbols = formatter.standaloneWeekdaySymbols ?? formatter.weekdaySymbols ?? []
        let weekdayIndex = max(1, min(schedule.weekday, weekdaySymbols.count)) - 1
        let weekday = weekdaySymbols.isEmpty ? "" : weekdaySymbols[weekdayIndex]

        formatter.timeStyle = .short
        formatter.dateStyle = .none

        // The separator between the day and the time is a word, and it is not "at" outside
        // English — de "um", fr "à", pt-BR "às". It has to come from the catalog like any
        // other copy.
        return String(
            format: SettingsL10n.Main.reminderScheduleWeekdayTime(bundle: bundle, locale: locale),
            weekday,
            formatter.string(from: reminderTimeDate(for: schedule, calendar: calendar))
        )
    }

    /// The cleanup reminder section's footer text: premium copy is static, free copy has to carry
    /// the formatted default schedule rather than a spelled-out time.
    ///
    /// The free schedule has to be *formatted*, not spelled out in the copy. The row directly
    /// above renders the same schedule through `DateFormatter`, which follows the reader's
    /// 12/24-hour setting and region — so any time written into the string is wrong for half
    /// the readers. Found on a 24-hour device, where the row said "18:00" and the sentence
    /// below it said "6:00 PM".
    static func footerText(
        hasPremiumAccess: Bool,
        calendar: Calendar,
        locale: Locale,
        bundle: Bundle? = nil
    ) -> String {
        if hasPremiumAccess {
            return SettingsL10n.string("settings.main.premiumLetsChooseCustomWeekly", bundle: bundle, locale: locale)
        }

        return String(
            format: SettingsL10n.Main.freeRemindersUseSundayAt(bundle: bundle, locale: locale),
            scheduleDescription(.defaultWeekly, calendar: calendar, locale: locale, bundle: bundle)
        )
    }

    /// A `Date` carrying today's date with the schedule's hour/minute, for `DateFormatter` and
    /// the reminder time `DatePicker` binding to work from.
    static func reminderTimeDate(for schedule: CleanupReminderSchedule, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = schedule.hour
        components.minute = schedule.minute
        return calendar.date(from: components) ?? Date()
    }
}
