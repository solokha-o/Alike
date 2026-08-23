import Foundation

public extension Locale {
    /// The locale Alike formats **technical values** in: counts, byte sizes and the timestamps
    /// that say when a scan or a cleanup ran.
    ///
    /// Adding Arabic (task 45) made an inconsistency visible that twelve Latin-digit locales had
    /// hidden. `ar_SA` asks for Arabic-Indic digits and the Umm al-Qura calendar, and Foundation
    /// obliges — `ByteCountFormatter`, `Date.formatted` and `String(localized:)` all follow
    /// `Locale.current`. `String(format:)` called without a `locale:` argument does not, and
    /// digits typed literally into translated copy do not either. The result was one screen
    /// showing the same count as `36` and `٣٦`, next to a Hijri date, next to `٥١٫٣ م.ب.`.
    ///
    /// Alike's numbers are technical rather than prose: a file size, a photo count, the moment a
    /// scan finished. They are pinned to Western digits and the Gregorian calendar so that every
    /// number in the app agrees with every other one, and so that the subscription disclosure —
    /// which must stay byte-identical to `Docs/legal/subscription-disclosure.md` and to the
    /// landing site — is not the odd one out.
    ///
    /// This is deliberately unconditional rather than an `if language == "ar"` special case. The
    /// twelve other shipped locales already use Western digits and the Gregorian calendar, so it
    /// changes nothing for them, and it means the next right-to-left or non-Gregorian language
    /// arrives already consistent instead of reopening this decision.
    static var alikeFormatting: Locale {
        var components = Locale.Components(locale: .current)
        components.numberingSystem = Locale.NumberingSystem("latn")
        components.calendar = .gregorian
        return Locale(components: components)
    }
}

public extension Calendar {
    /// `Locale.alikeFormatting`'s calendar, for the formatters that take a calendar separately.
    ///
    /// The time zone still comes from the device: pinning the calendar is about which era and
    /// month names a date is spelled in, not about pretending the user is somewhere else.
    static var alikeFormattingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .alikeFormatting
        calendar.timeZone = Calendar.current.timeZone
        return calendar
    }
}

public extension String {
    /// A byte count formatted the way the whole app formats byte counts.
    ///
    /// `ByteCountFormatter` has no `locale` property and reads `Locale.current` internally, so
    /// pinning the digits means going through `ByteCountFormatStyle`, which does take one.
    static func alikeByteCount(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(.alikeFormatting))
    }
}

public extension Date {
    /// A timestamp formatted the way the whole app formats timestamps.
    func alikeFormatted(
        date: Date.FormatStyle.DateStyle,
        time: Date.FormatStyle.TimeStyle
    ) -> String {
        var style = Date.FormatStyle(date: date, time: time)
            .locale(.alikeFormatting)
        style.calendar = .alikeFormattingCalendar
        style.timeZone = Calendar.alikeFormattingCalendar.timeZone
        return formatted(style)
    }
}
