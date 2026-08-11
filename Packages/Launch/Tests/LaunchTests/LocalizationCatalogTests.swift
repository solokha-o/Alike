import XCTest

/// This package owns its own string catalog (localization foundation, task 39).
///
/// SwiftPM copies `.xcstrings` verbatim instead of running `xcstringstool`, so `String(localized:)`
/// cannot be exercised from `swift test` — it would resolve to the key. What can be checked here,
/// and what actually breaks in practice, is whether the generated wrapper and the catalog still
/// agree and whether every shipped key carries every language.
struct LocalizationCatalog {
    static let targetName = "Launch"
    static let wrapperName = "LaunchL10n"
    static let modulePrefix = "launch."
    /// Keys that are deliberately English-only until a translation pass picks them up.
    static let untranslated: Set<String> = []

    let strings: [String: [String: Any]]

    static func packageRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()  // Tests/<target>Tests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
    }

    static func load(file: StaticString = #filePath) throws -> LocalizationCatalog {
        let url = packageRoot(file: file)
            .appendingPathComponent("Sources/\(targetName)/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = (json as? [String: Any])?["strings"] as? [String: [String: Any]]
        return LocalizationCatalog(strings: try XCTUnwrap(strings))
    }

    /// The keys the generated wrapper resolves, read back out of the wrapper source.
    static func wrapperKeys(file: StaticString = #filePath) throws -> Set<String> {
        let url = packageRoot(file: file)
            .appendingPathComponent("Sources/\(targetName)/Localization/\(wrapperName).swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"(?:string|plural)\("([^"]+)"[,)]"#)
        let range = NSRange(source.startIndex..., in: source)
        return Set(pattern.matches(in: source, range: range).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        })
    }

    func localizations(of key: String) throws -> [String: [String: Any]] {
        let entry = try XCTUnwrap(strings[key], "missing key \(key)")
        return try XCTUnwrap(
            entry["localizations"] as? [String: [String: Any]],
            "no localizations for \(key)"
        )
    }

    func pluralCategories(of key: String, language: String) throws -> [String] {
        try plurals(key, language: language).keys.sorted()
    }

    func plural(_ key: String, language: String, category: String) throws -> String {
        let unit = try XCTUnwrap(plurals(key, language: language)[category] as? [String: Any])
        let stringUnit = try XCTUnwrap(unit["stringUnit"] as? [String: Any])
        return try XCTUnwrap(stringUnit["value"] as? String)
    }

    private func plurals(_ key: String, language: String) throws -> [String: Any] {
        let variations = try XCTUnwrap(
            localizations(of: key)[language]?["variations"] as? [String: Any],
            "\(key) has no variations in \(language)"
        )
        return try XCTUnwrap(variations["plural"] as? [String: Any])
    }
}

final class LocalizationCatalogTests: XCTestCase {
    func testEveryWrapperKeyExistsInTheCatalog() throws {
        let catalog = try LocalizationCatalog.load()
        let missing = try LocalizationCatalog.wrapperKeys().subtracting(catalog.strings.keys)

        XCTAssertTrue(
            missing.isEmpty,
            "wrapper resolves keys the catalog does not define: \(missing.sorted())"
        )
    }

    func testEveryKeyIsNamespacedToThisModule() throws {
        let catalog = try LocalizationCatalog.load()
        let foreign = catalog.strings.keys.filter { !$0.hasPrefix(LocalizationCatalog.modulePrefix) }

        XCTAssertTrue(
            foreign.isEmpty,
            "keys outside the \(LocalizationCatalog.modulePrefix) namespace: \(foreign.sorted())"
        )
    }

    /// Guards the split itself: a key that lost its Ukrainian value on the way into this package
    /// would otherwise only surface as English text in a Ukrainian build.
    func testEveryKeyCarriesEnglishAndUkrainian() throws {
        let catalog = try LocalizationCatalog.load()
        var incomplete: [String] = []

        for key in catalog.strings.keys.sorted() {
            let localizations = try catalog.localizations(of: key)
            if localizations["en"] == nil {
                incomplete.append("\(key) [en]")
            }
            if localizations["uk"] == nil, !LocalizationCatalog.untranslated.contains(key) {
                incomplete.append("\(key) [uk]")
            }
        }

        XCTAssertTrue(incomplete.isEmpty, "incomplete entries: \(incomplete)")
    }
}
