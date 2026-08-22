import Foundation
import XCTest

/// Builds a real, loadable `.lproj` bundle out of the package's own `Localizable.xcstrings`.
///
/// SwiftPM copies `.xcstrings` verbatim instead of running `xcstringstool`, so `Bundle.module`
/// under `swift test` contains no compiled plural data and every lookup falls back to its key.
/// Asserting on the catalog JSON alone would prove the plural categories exist but not that
/// Foundation selects the right one for a count, or that `%1$lld` / `%2$@` are substituted in the
/// right order. This fixture performs the same conversion `xcstringstool` performs — plain entries
/// into `Localizable.strings`, plural variations into `Localizable.stringsdict` — so the tests can
/// exercise the production lookup path against compiled resources.
///
/// The fixture is derived from the shipped catalog at test time, so it cannot drift from it.
enum CompiledCatalogFixture {
    /// Mirrors the structure `xcstringstool` emits, verified against the `uk.lproj` payload in a
    /// built `DesignSystem_DesignSystem.bundle`.
    private static let formatKey = "NSStringLocalizedFormatKey"
    private static let specTypeKey = "NSStringFormatSpecTypeKey"
    private static let valueTypeKey = "NSStringFormatValueTypeKey"
    private static let substitution = "value"

    /// Returns the compiled bundle for a single language. Resolution is per-`.lproj` on purpose:
    /// `String(localized:bundle:locale:)` takes its plural rules from `locale`, but picks the
    /// language from the bundle's own localizations, so a multi-language bundle would answer in
    /// its development region no matter what locale the caller passed.
    static func bundle(language: String, file: StaticString = #filePath) throws -> Bundle {
        let root = try compile(file: file)
        let lproj = root.appendingPathComponent("\(language).lproj")
        return try XCTUnwrap(Bundle(url: lproj), "no compiled resources for \(language)")
    }

    private static func compile(file: StaticString) throws -> URL {
        let catalog = try LocalizationCatalog.load(file: file)
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DesignSystemLocalization-\(UUID().uuidString)")
            .appendingPathComponent("Localization.bundle")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try infoPlist().write(to: root.appendingPathComponent("Info.plist"))

        for language in languages(in: catalog) {
            let lproj = root.appendingPathComponent("\(language).lproj")
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)

            var plain: [String: String] = [:]
            var plurals: [String: Any] = [:]

            for (key, entry) in catalog.strings {
                guard let localization = (entry["localizations"] as? [String: Any])?[language] as? [String: Any] else {
                    continue
                }
                if let unit = localization["stringUnit"] as? [String: Any],
                   let value = unit["value"] as? String {
                    plain[key] = value
                } else if let variations = localization["variations"] as? [String: Any],
                          let plural = variations["plural"] as? [String: Any] {
                    plurals[key] = pluralEntry(plural)
                }
            }

            try write(plain, to: lproj.appendingPathComponent("Localizable.strings"))
            try write(plurals, to: lproj.appendingPathComponent("Localizable.stringsdict"))
        }

        return root
    }

    private static func pluralEntry(_ plural: [String: Any]) -> [String: Any] {
        var substitution: [String: Any] = [
            specTypeKey: "NSStringPluralRuleType",
            valueTypeKey: "lld"
        ]
        for (category, unit) in plural {
            if let value = (unit as? [String: Any])?["stringUnit"] as? [String: Any],
               let string = value["value"] as? String {
                substitution[category] = string
            }
        }
        return [formatKey: "%#@\(Self.substitution)@", Self.substitution: substitution]
    }

    private static func languages(in catalog: LocalizationCatalog) -> Set<String> {
        var found: Set<String> = []
        for entry in catalog.strings.values {
            for language in (entry["localizations"] as? [String: Any])?.keys ?? [:].keys {
                found.insert(language)
            }
        }
        return found
    }

    private static func infoPlist() throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": "com.alike.tests.cleanup.localization",
                "CFBundleDevelopmentRegion": "en",
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundlePackageType": "BNDL"
            ],
            format: .xml,
            options: 0
        )
    }

    private static func write(_ contents: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: contents,
            format: .binary,
            options: 0
        )
        try data.write(to: url)
    }
}
