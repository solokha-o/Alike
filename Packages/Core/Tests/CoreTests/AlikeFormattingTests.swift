import XCTest
@testable import Core

/// The pinned-formatting guard (task 45).
///
/// Arabic is the first shipped locale whose defaults disagree with the rest: `ar_SA` asks for
/// Arabic-Indic digits and the Umm al-Qura calendar. `Locale.alikeFormatting` pins technical
/// values back to Western digits and the Gregorian calendar, and these tests hold both halves
/// of that promise — that the pin actually changes what `ar_SA` renders, and that no user-facing
/// call site formats a number or a date around it.
final class AlikeFormattingTests: XCTestCase {
    private let arabic = Locale(identifier: "ar_SA")

    private var pinnedArabic: Locale { .alikeFormatting(basedOn: Locale(identifier: "ar_SA")) }

    // MARK: - The pin changes what ar_SA renders

    func testArabicBaseKeepsItsLanguageButLosesArabicIndicDigits() {
        XCTAssertEqual(pinnedArabic.language.languageCode?.identifier, "ar")
        XCTAssertEqual(pinnedArabic.numberingSystem.identifier, "latn")
        XCTAssertEqual(pinnedArabic.calendar.identifier, .gregorian)
    }

    /// The paywall's scan-reset date (`PremiumPresentation`) and the cleanup history month
    /// header (`CleanupHistoryView`) both build their own field list and pin it.
    func testSpelledOutDatesUseLatinDigitsAndTheGregorianCalendar() {
        // 2026-03-04 12:00 UTC. Under Umm al-Qura this month is Ramadan 1447.
        let date = Date(timeIntervalSince1970: 1_772_625_600)
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
            .locale(pinnedArabic)
        style.calendar = .alikeFormattingCalendar(basedOn: arabic)
        style.timeZone = TimeZone(identifier: "UTC")!

        let rendered = date.formatted(style)
        XCTAssertTrue(rendered.contains("2026"), "expected a Gregorian year in \(rendered)")
        XCTAssertFalse(containsArabicIndicDigits(rendered), "Arabic-Indic digits in \(rendered)")
    }

    /// The scanner progress readout (`ScannerHomeComponents`, label and accessibility value).
    func testPercentagesUseLatinDigits() {
        let rendered = 0.36.formatted(
            .percent.precision(.fractionLength(0)).locale(pinnedArabic)
        )
        XCTAssertTrue(rendered.contains("36"), "expected Latin 36 in \(rendered)")
        XCTAssertFalse(containsArabicIndicDigits(rendered), "Arabic-Indic digits in \(rendered)")
    }

    /// Cluster badges (`CleanupView`), the grid column picker (`PhotoGridColumnPreference`)
    /// and the guide's step numbers (`GuideRows`).
    func testWholeNumbersUseLatinDigits() {
        let rendered = 36.formatted(.number.locale(pinnedArabic))
        XCTAssertEqual(rendered, "36")
    }

    /// The metadata sheet's megapixel count (`ClusterDetailsView`).
    func testDecimalNumbersUseLatinDigitsAndALatinDecimalSeparator() {
        let rendered = 51.3.formatted(
            FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
                .locale(pinnedArabic)
        )
        XCTAssertTrue(rendered.contains("51"), "expected Latin 51 in \(rendered)")
        XCTAssertFalse(containsArabicIndicDigits(rendered), "Arabic-Indic digits in \(rendered)")
        XCTAssertFalse(rendered.contains("٫"), "Arabic decimal separator in \(rendered)")
    }

    // MARK: - The shared styles carry the pin

    func testSharedStylesAllCarryThePinnedLocale() {
        XCTAssertEqual(FloatingPointFormatStyle<Double>.Percent.alikePercent.locale, .alikeFormatting)
        XCTAssertEqual(IntegerFormatStyle<Int>.alikeNumber.locale, .alikeFormatting)
        XCTAssertEqual(FloatingPointFormatStyle<Double>.alikeDecimal.locale, .alikeFormatting)

        let pinned = Date.FormatStyle(date: .abbreviated, time: .omitted).alikePinned
        XCTAssertEqual(pinned.locale, .alikeFormatting)
        XCTAssertEqual(pinned.calendar.identifier, .gregorian)
    }

    // MARK: - No call site formats around the pin

    /// The five sites named in review were not the whole set — three `format: .number` badges
    /// bypassed the helper too. This scans every package source so the next one cannot land
    /// quietly.
    ///
    /// `String(format:)` without a `locale:` argument is deliberately not covered: it is
    /// non-localized already, which is why the pinned digits and its digits agree.
    func testNoPackageSourceFormatsAValueOutsideThePinnedLocale() throws {
        var offenders: [String] = []

        for package in try packageDirectories() {
            let sources = package.appendingPathComponent("Sources")
            guard FileManager.default.fileExists(atPath: sources.path) else { continue }
            let enumerator = try XCTUnwrap(
                FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
            )
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                if url.lastPathComponent == "Locale+AlikeFormatting.swift" { continue }
                let source = try String(contentsOf: url, encoding: .utf8)
                for (line, statement) in Self.statements(in: source) {
                    guard statement.contains(".formatted(") || statement.contains("format: .") else { continue }
                    guard !statement.lowercased().contains("alike") else { continue }
                    // A `.formatted()` with no style argument at all is the locale-sensitive
                    // default, and so is caught here too.
                    offenders.append("\(package.lastPathComponent)/\(url.lastPathComponent):\(line): \(statement)")
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            These values format with Locale.current, so ar_SA renders them in Arabic-Indic \
            digits (and dates in Umm al-Qura) next to the pinned values around them. Route them \
            through .alikePinned / .alikePercent / .alikeNumber / .alikeDecimal:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    // MARK: - Helpers

    private func containsArabicIndicDigits(_ string: String) -> Bool {
        string.unicodeScalars.contains { ("\u{0660}"..."\u{0669}").contains($0) || ("\u{06F0}"..."\u{06F9}").contains($0) }
    }

    /// The file's lines, with a line that leaves parentheses open joined to the ones that
    /// close them. A `.formatted(` call wrapped across four lines is one statement to scan,
    /// not one hit and three invisible continuations.
    private static func statements(in source: String) -> [(line: Int, text: String)] {
        var statements: [(line: Int, text: String)] = []
        var buffer = ""
        var startLine = 1
        var depth = 0

        for (offset, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if buffer.isEmpty {
                startLine = offset + 1
                buffer = trimmed
            } else {
                buffer += " " + trimmed
            }
            depth += trimmed.filter { $0 == "(" }.count - trimmed.filter { $0 == ")" }.count
            if depth <= 0 {
                statements.append((line: startLine, text: buffer))
                buffer = ""
                depth = 0
            }
        }
        if !buffer.isEmpty {
            statements.append((line: startLine, text: buffer))
        }
        return statements
    }

    private func packageDirectories() throws -> [URL] {
        let packagesRoot = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()  // Tests/CoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // Core
            .deletingLastPathComponent()  // Packages
        return try FileManager.default.contentsOfDirectory(
            at: packagesRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("Package.swift").path)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
