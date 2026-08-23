import XCTest

/// This package owns its own string catalog (localization foundation, task 39).
///
/// SwiftPM copies `.xcstrings` verbatim instead of running `xcstringstool`, so `String(localized:)`
/// cannot be exercised from `swift test` — it would resolve to the key. What can be checked here,
/// and what actually breaks in practice, is whether the generated wrapper and the catalog still
/// agree and whether every shipped key carries every language.
struct LocalizationCatalog {
    static let targetName = "Welcome"
    static let wrapperName = "WelcomeL10n"
    static let modulePrefix = "welcome."
    /// Keys that are deliberately English-only until a translation pass picks them up.
    static let untranslated: Set<String> = []

    /// Every language the app ships. Adding one here makes the whole suite fail until the
    /// catalog carries it — which is the point.
    static let shippedLanguages = [
        "en", "uk", "es-419", "es", "pt-BR", "de", "fr", "it", "nl", "pl", "tr", "zh-Hant",
        "ar"
    ]

    /// The CLDR plural categories each shipped language actually uses. `ar` needs all six —
    /// it is the only shipped language with `zero` and `two`; `uk` and `pl` need four;
    /// `pt-BR` and `fr` add `many` for compact large numbers; `zh-Hant` has a single form,
    /// so a one/other pair there would be two spellings of the same sentence; everything else
    /// uses one/other.
    static func pluralCategories(for language: String) -> [String] {
        switch language {
        case "ar": ["few", "many", "one", "other", "two", "zero"]
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

    /// A single `stringUnit` value, or nil for a plural entry.
    static func value(of localization: [String: Any]?) -> String? {
        (localization?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    /// Every string a localization actually ships: one value for a plain entry, or one per
    /// plural category. Plural variations are the half `value(of:)` cannot reach, and the
    /// format-shape check needs them — a plural category is a format string like any other,
    /// and the keys carrying two arguments live there.
    static func values(of localization: [String: Any]?) -> [(category: String, value: String)] {
        if let value = value(of: localization) {
            return [(category: "", value: value)]
        }
        guard
            let variations = localization?["variations"] as? [String: Any],
            let plural = variations["plural"] as? [String: Any]
        else {
            return []
        }
        return plural.keys.sorted().compactMap { category in
            guard
                let unit = plural[category] as? [String: Any],
                let stringUnit = unit["stringUnit"] as? [String: Any],
                let value = stringUnit["value"] as? String
            else {
                return nil
            }
            return (category: category, value: value)
        }
    }

    /// The shape English states for a key. Every plural category of one language carries the
    /// same arguments — only the wording around them differs — so `other`, the one category
    /// every language declares, stands for the key.
    static func referenceShape(
        _ localization: [String: Any]?
    ) -> (specifiers: [String], literalPercents: Int)? {
        let candidates = values(of: localization)
        guard let reference = candidates.first(where: { $0.category == "other" }) ?? candidates.first else {
            return nil
        }
        return formatShape(reference.value)
    }

    /// Conversion specifiers in sorted order, plus the count of literal `%%`. Sorting is
    /// deliberate: a language may put the number before or after the sign, or reorder
    /// positional arguments, and still be a faithful translation.
    static func formatShape(_ value: String) -> (specifiers: [String], literalPercents: Int) {
        var specifiers: [String] = []
        var literalPercents = 0
        var characters = Array(value)
        var index = 0

        while index < characters.count {
            guard characters[index] == "%" else {
                index += 1
                continue
            }
            var cursor = index + 1
            if cursor < characters.count, characters[cursor] == "%" {
                literalPercents += 1
                index = cursor + 1
                continue
            }
            var specifier = "%"
            while cursor < characters.count, !"@dfsuxX".contains(characters[cursor]) {
                specifier.append(characters[cursor])
                cursor += 1
            }
            if cursor < characters.count {
                specifier.append(characters[cursor])
                specifiers.append(specifier)
                cursor += 1
            }
            index = cursor
        }

        return (specifiers.sorted(), literalPercents)
    }

    /// A `%` that never resolves into a specifier or a literal — `String(format:)` reads
    /// whatever follows it as a conversion and prints garbage or drops the tail.
    static func hasDanglingPercent(_ value: String) -> Bool {
        var characters = Array(value)
        var index = 0

        while index < characters.count {
            guard characters[index] == "%" else {
                index += 1
                continue
            }
            var cursor = index + 1
            if cursor < characters.count, characters[cursor] == "%" {
                index = cursor + 1
                continue
            }
            while cursor < characters.count, !"@dfsuxX".contains(characters[cursor]) {
                cursor += 1
            }
            if cursor >= characters.count { return true }
            index = cursor + 1
        }

        return false
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
    /// Format specifiers have to survive translation, but their *order* does not.
    ///
    /// Turkish writes a percentage as `%50`, so `tr` legitimately carries
    /// `Kitaplığın taranıyor… %%%d` where English carries `Scanning your library… %d%%`.
    /// Comparing the rendered shape position by position would call that a bug; comparing
    /// the multiset of conversion specifiers plus the number of literal `%%` calls it what
    /// it is — the same format, written the way the language writes it.
    ///
    /// What this does catch is a translation that drops an argument, invents one, loses the
    /// literal percent sign, or leaves a dangling `%` that `String(format:)` would read as
    /// the start of a specifier.
    ///
    /// Plural variations are checked category by category, not skipped: each category is a
    /// format string in its own right, and the keys carrying two arguments — a count and a
    /// formatted byte count — are exactly the ones that live in variations.
    func testFormatSpecifiersSurviveEveryTranslation() throws {
        let catalog = try LocalizationCatalog.load()
        var mismatched: [String] = []

        for key in catalog.strings.keys.sorted() {
            let localizations = try catalog.localizations(of: key)
            guard let englishShape = LocalizationCatalog.referenceShape(localizations["en"]) else {
                continue
            }
            for (language, unit) in localizations.sorted(by: { $0.key < $1.key }) {
                // Plain entries yield one unlabelled value; plural entries yield one per
                // category, each checked in its own right.
                for (category, translation) in LocalizationCatalog.values(of: unit) {
                    let label = category.isEmpty
                        ? "\(key) [\(language)]"
                        : "\(key) [\(language).\(category)]"
                    let shape = LocalizationCatalog.formatShape(translation)
                    if shape != englishShape {
                        mismatched.append("\(label) has \(shape) where en has \(englishShape)")
                    }
                    if LocalizationCatalog.hasDanglingPercent(translation) {
                        mismatched.append("\(label) ends on a dangling %")
                    }
                }
            }
        }

        XCTAssertTrue(mismatched.isEmpty, "format specifiers changed in translation: \(mismatched)")
    }
}
