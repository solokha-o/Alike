import Foundation

extension Locale {
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
    public static var alikeFormatting: Locale { alikeFormatting(basedOn: .current) }

    /// `alikeFormatting` derived from an explicit base rather than from `Locale.current`.
    ///
    /// The device locale is not settable from a test, and the whole point of the pin is what it
    /// does to `ar_SA`, so the derivation is exposed as a function and the property is the
    /// `Locale.current` call of it.
    public static func alikeFormatting(basedOn base: Locale) -> Locale {
        var components = Locale.Components(locale: base)
        components.numberingSystem = Locale.NumberingSystem("latn")
        components.calendar = .gregorian
        return Locale(components: components)
    }
}

extension Calendar {
    /// `Locale.alikeFormatting`'s calendar, for the formatters that take a calendar separately.
    ///
    /// The time zone still comes from the device: pinning the calendar is about which era and
    /// month names a date is spelled in, not about pretending the user is somewhere else.
    public static var alikeFormattingCalendar: Calendar { alikeFormattingCalendar(basedOn: .current) }

    /// `alikeFormattingCalendar` derived from an explicit base locale — the test seam that
    /// `Locale.alikeFormatting(basedOn:)` is.
    public static func alikeFormattingCalendar(basedOn base: Locale) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .alikeFormatting(basedOn: base)
        calendar.timeZone = Calendar.current.timeZone
        return calendar
    }
}

extension String {
    /// A byte count formatted the way the whole app formats byte counts.
    ///
    /// `ByteCountFormatter` has no `locale` property and reads `Locale.current` internally, so
    /// pinning the digits means going through `ByteCountFormatStyle`, which does take one.
    public static func alikeByteCount(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(.alikeFormatting))
    }
}

extension Date {
    /// A timestamp formatted the way the whole app formats timestamps.
    public func alikeFormatted(
        date: Date.FormatStyle.DateStyle,
        time: Date.FormatStyle.TimeStyle
    ) -> String {
        formatted(Date.FormatStyle(date: date, time: time).alikePinned)
    }
}

extension Date.FormatStyle {
    /// The same style, pinned to `Locale.alikeFormatting` and its calendar.
    ///
    /// `alikeFormatted(date:time:)` covers the two canned styles Alike shows most often. A
    /// screen that needs its own field list — "March 4, 2026" on the paywall, "March 2026" as
    /// a history header — builds the style itself and pins it here, so it does not have to
    /// remember the calendar and time-zone half of the pinning.
    public var alikePinned: Date.FormatStyle {
        var style = locale(.alikeFormatting)
        style.calendar = .alikeFormattingCalendar
        style.timeZone = Calendar.alikeFormattingCalendar.timeZone
        return style
    }
}

extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Percent {
    /// A whole-number percentage formatted the way the whole app formats percentages.
    public static var alikePercent: FloatingPointFormatStyle<Double>.Percent {
        .percent.precision(.fractionLength(0)).locale(.alikeFormatting)
    }
}

extension FormatStyle where Self == IntegerFormatStyle<Int> {
    /// A whole number formatted the way the whole app formats whole numbers.
    ///
    /// `.number` reads `Locale.current`, so a bare `Text(count, format: .number)` prints
    /// `٣٦` under `ar_SA` next to a `36` that came from a pinned formatter.
    public static var alikeNumber: IntegerFormatStyle<Int> {
        .number.locale(.alikeFormatting)
    }
}

extension FormatStyle where Self == FloatingPointFormatStyle<Double> {
    /// A decimal number formatted the way the whole app formats decimal numbers.
    public static var alikeDecimal: FloatingPointFormatStyle<Double> {
        .number.locale(.alikeFormatting)
    }
}
