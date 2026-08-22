import Foundation
import XCTest

/// Builds a real, loadable `.lproj` bundle out of the package's own `Localizable.xcstrings`.
///
/// SwiftPM copies `.xcstrings` verbatim instead of running `xcstringstool`, so `Bundle.module`
/// under `swift test` contains no compiled resources and every lookup falls back to its key.
/// Asserting on the catalog JSON alone would prove the copy exists but not that `DateFormatter`
/// output actually lands inside it via `%@`. This fixture performs the same conversion
/// `xcstringstool` performs — plain entries into `Localizable.strings` — so the tests can
/// exercise the production lookup path against compiled resources.
///
/// The fixture is derived from the shipped catalog at test time, so it cannot drift from it.
/// Mirrors `Packages/Core/Tests/CoreTests/CompiledCatalogFixture.swift`; this package has no
/// plural variations yet, so only the plain-entry half is needed.
enum CompiledCatalogFixture {
    /// Returns the compiled bundle for a single language. Resolution is per-`.lproj` on purpose:
    /// `String(localized:bundle:locale:)` picks the language from the bundle's own localizations,
    /// not from `locale`, so a multi-language bundle would answer in its development region no
    /// matter what locale the caller passed.
    static func bundle(language: String, file: StaticString = #filePath) throws -> Bundle {
        let root = try compile(file: file)
        let lproj = root.appendingPathComponent("\(language).lproj")
        return try XCTUnwrap(Bundle(url: lproj), "no compiled resources for \(language)")
    }

    private static func compile(file: StaticString) throws -> URL {
        let catalog = try LocalizationCatalog.load(file: file)
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SettingsLocalization-\(UUID().uuidString)")
            .appendingPathComponent("Localization.bundle")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try infoPlist().write(to: root.appendingPathComponent("Info.plist"))

        for language in languages(in: catalog) {
            let lproj = root.appendingPathComponent("\(language).lproj")
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)

            var plain: [String: String] = [:]
            for (key, entry) in catalog.strings {
                guard let localization = (entry["localizations"] as? [String: Any])?[language] as? [String: Any],
                      let unit = localization["stringUnit"] as? [String: Any],
                      let value = unit["value"] as? String else {
                    continue
                }
                plain[key] = value
            }

            try write(plain, to: lproj.appendingPathComponent("Localizable.strings"))
        }

        return root
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
                "CFBundleIdentifier": "com.alike.tests.settings.localization",
                "CFBundleDevelopmentRegion": "en",
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundlePackageType": "BNDL"
            ],
            format: .xml,
            options: 0
        )
    }

    private static func write(_ contents: [String: String], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: contents,
            format: .binary,
            options: 0
        )
        try data.write(to: url)
    }
}
