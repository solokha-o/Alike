import XCTest

/// This package owns its own string catalog (localization foundation, task 39).
///
/// SwiftPM copies `.xcstrings` verbatim instead of running `xcstringstool`, so `String(localized:)`
/// cannot be exercised from `swift test` — it would resolve to the key. What can be checked here,
/// and what actually breaks in practice, is whether the generated wrapper and the catalog still
/// agree and whether every shipped key carries every language.
struct LocalizationCatalog {
    static let targetName = "UserGuide"
    static let wrapperName = "UserGuideL10n"
    static let modulePrefix = "userGuide."
    /// Keys that are deliberately English-only until a translation pass picks them up.
    static let untranslated: Set<String> = []

    /// Every language the app ships. Adding one here makes the whole suite fail until the
    /// catalog carries it — which is the point.
    static let shippedLanguages = [
        "en", "uk", "es-419", "es", "pt-BR", "de", "fr", "it", "nl", "pl", "tr", "zh-Hant"
    ]

    /// The CLDR plural categories each shipped language actually uses. `uk` and `pl` need all
    /// four; `pt-BR` and `fr` add `many` for compact large numbers; `zh-Hant` has a single form,
    /// so a one/other pair there would be two spellings of the same sentence; everything else
    /// uses one/other.
    static func pluralCategories(for language: String) -> [String] {
        switch language {
        case "uk", "pl": ["few", "many", "one", "other"]
        case "pt-BR", "fr": ["many", "one", "other"]
        case "zh-Hant": ["other"]
        default: ["one", "other"]
        }
    }

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

    /// The check that catches a catalog which silently missed one of the shipped languages —
    /// the failure mode of a translation pass is a locale that is 99% there, not one that is absent.
    func testEveryKeyCarriesEveryShippedLanguage() throws {
        let catalog = try LocalizationCatalog.load()
        var incomplete: [String] = []

        for key in catalog.strings.keys.sorted() {
            let localizations = try catalog.localizations(of: key)
            for language in LocalizationCatalog.shippedLanguages where localizations[language] == nil {
                guard language == "en" || !LocalizationCatalog.untranslated.contains(key) else {
                    continue
                }
                incomplete.append("\(key) [\(language)]")
            }
        }

        XCTAssertTrue(incomplete.isEmpty, "incomplete entries: \(incomplete)")
    }

    /// A plural key missing `many` in `fr` or `pt-BR` does not fail to build — it silently falls
    /// back to `other`, which is right for those two only by accident and wrong the moment a
    /// language with real distinctions is added.
    func testEveryPluralKeyDeclaresEveryCategoryOfItsLanguage() throws {
        let catalog = try LocalizationCatalog.load()
        var wrong: [String] = []

        for key in catalog.strings.keys.sorted() {
            for language in LocalizationCatalog.shippedLanguages {
                guard let localization = try catalog.localizations(of: key)[language],
                      localization["variations"] != nil else { continue }
                let declared = try catalog.pluralCategories(of: key, language: language)
                let expected = LocalizationCatalog.pluralCategories(for: language)
                if declared != expected {
                    wrong.append("\(key) [\(language)]: \(declared) != \(expected)")
                }
            }
        }

        XCTAssertTrue(wrong.isEmpty, "wrong plural categories: \(wrong)")
    }

    /// The counterpart of the check above: a key that is plural in English has to be plural in
    /// every language, or that language quietly ships one grammatical form for every count.
    func testPluralKeysArePluralInEveryLanguage() throws {
        let catalog = try LocalizationCatalog.load()
        var flat: [String] = []

        for key in catalog.strings.keys.sorted() {
            let localizations = try catalog.localizations(of: key)
            guard localizations["en"]?["variations"] != nil else { continue }
            for language in LocalizationCatalog.shippedLanguages
            where localizations[language]?["variations"] == nil {
                flat.append("\(key) [\(language)]")
            }
        }

        XCTAssertTrue(flat.isEmpty, "plural in en but not in: \(flat)")
    }
}
