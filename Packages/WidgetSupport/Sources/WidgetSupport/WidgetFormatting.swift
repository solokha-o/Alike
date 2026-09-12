import Foundation

/// The formatting pin from `Core`'s `Locale+AlikeFormatting`, restated here.
///
/// `WidgetSupport` cannot import `Core` — the whole point of the package is that the
/// extension links nothing else — so the pin is duplicated rather than shared. What the
/// duplicate has to preserve is the property `Core` documents: under a locale that asks
/// for Arabic-Indic digits and a non-Gregorian calendar, Alike still prints Western
/// digits and Gregorian dates, so a figure in the widget cannot be spelled differently
/// from the same figure on the scanner screen. `WidgetFormattingTests` asserts exactly
/// that against `ar_SA`, which is the locale that made the inconsistency visible.
public enum WidgetFormatting {
    /// Western digits, Gregorian calendar, derived from the device locale.
    public static var locale: Locale { locale(basedOn: .current) }

    public static func locale(basedOn base: Locale) -> Locale {
        var components = Locale.Components(locale: base)
        components.numberingSystem = Locale.NumberingSystem("latn")
        components.calendar = .gregorian
        return Locale(components: components)
    }

    public static var calendar: Calendar { calendar(basedOn: .current) }

    public static func calendar(basedOn base: Locale) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale(basedOn: base)
        calendar.timeZone = Calendar.current.timeZone
        return calendar
    }

    /// A byte count spelled the way the rest of the app spells byte counts.
    public static func byteCount(_ bytes: Int64, basedOn base: Locale = .current) -> String {
        bytes.formatted(.byteCount(style: .file).locale(locale(basedOn: base)))
    }

    /// The byte count prefixed with «≈», the way the concept spells the estimate.
    ///
    /// The estimate is a heuristic the scanner screen also shows as an estimate; the
    /// sign says so on the widget, where there is no sentence around it to.
    public static func approximateByteCount(_ bytes: Int64, basedOn base: Locale = .current) -> String {
        "\u{2248}" + byteCount(bytes, basedOn: base)
    }

    /// A whole number spelled the way the rest of the app spells whole numbers.
    public static func number(_ value: Int, basedOn base: Locale = .current) -> String {
        value.formatted(.number.locale(locale(basedOn: base)))
    }

    /// A timestamp spelled the way the rest of the app spells timestamps.
    public static func timestamp(
        _ date: Date,
        dateStyle: Date.FormatStyle.DateStyle = .abbreviated,
        timeStyle: Date.FormatStyle.TimeStyle = .shortened,
        basedOn base: Locale = .current
    ) -> String {
        var style = Date.FormatStyle(date: dateStyle, time: timeStyle)
            .locale(locale(basedOn: base))
        style.calendar = calendar(basedOn: base)
        style.timeZone = calendar(basedOn: base).timeZone
        return date.formatted(style)
    }
}
