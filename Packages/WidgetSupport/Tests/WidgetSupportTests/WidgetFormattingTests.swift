import Foundation
import Testing
@testable import WidgetSupport

@Suite("Widget number and date formatting")
struct WidgetFormattingTests {
    /// The locale that made the app-wide pin necessary: `ar_SA` asks Foundation for
    /// Arabic-Indic digits and the Umm al-Qura calendar, and Foundation obliges.
    private let arabic = Locale(identifier: "ar_SA")

    @Test("Byte counts use Western digits even under a locale that asks for Arabic-Indic ones")
    func byteCountDigits() {
        let formatted = WidgetFormatting.byteCount(1_932_735_283, basedOn: arabic)
        #expect(formatted.contains { $0.isASCIIDigit })
        #expect(!formatted.contains { $0.isArabicIndicDigit })
    }

    @Test("Whole numbers use Western digits under the same locale")
    func numberDigits() {
        let formatted = WidgetFormatting.number(24, basedOn: arabic)
        #expect(formatted.contains("24"))
        #expect(!formatted.contains { $0.isArabicIndicDigit })
    }

    @Test("Timestamps use the Gregorian calendar under a locale whose default is not")
    func calendarPin() {
        #expect(WidgetFormatting.calendar(basedOn: arabic).identifier == .gregorian)
        let formatted = WidgetFormatting.timestamp(
            Date(timeIntervalSince1970: 1_770_000_000),
            basedOn: arabic
        )
        // 2026 in Gregorian, 1447 in Umm al-Qura — the year is the tell.
        #expect(formatted.contains("2026"))
        #expect(!formatted.contains { $0.isArabicIndicDigit })
    }

    @Test("The pin leaves the twelve Latin-digit locales alone")
    func latinLocalesUnchanged() {
        let base = Locale(identifier: "de_DE")
        #expect(WidgetFormatting.byteCount(1_000_000, basedOn: base)
            == Int64(1_000_000).formatted(.byteCount(style: .file).locale(base)))
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    /// U+0660–U+0669 and the Extended Arabic-Indic block U+06F0–U+06F9.
    var isArabicIndicDigit: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
        return (0x0660...0x0669).contains(Int(scalar.value))
            || (0x06F0...0x06F9).contains(Int(scalar.value))
    }
}
