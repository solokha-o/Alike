import Foundation
import Testing

/// The app target owns `Alike/Alike/Localizable.xcstrings`, which after task 40 holds app-level
/// strings only — the rescan alert and the tab titles. Every text-owning package has had this
/// gate since task 39; the app catalog was the one catalog nothing checked.
///
/// The catalog file is read directly rather than through `String(localized:)`: the assertions are
/// about what ships to translators, and a resolved string would only prove the running bundle.
struct LocalizationCatalog {
    static let wrapperName = "AlikeL10n"
    static let modulePrefix = "alike."
    /// Every language the app ships. Adding one here makes the suite fail until the catalog
    /// carries it — which is the point.
    static let shippedLanguages = [
        "en", "uk", "es-419", "es", "pt-BR", "de", "fr", "it", "nl", "pl", "tr", "zh-Hant",
        "ar"
    ]

    let strings: [String: [String: Any]]

    static func appRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()  // AlikeTests
            .deletingLastPathComponent()  // Alike (project folder)
    }

    static func load(file: StaticString = #filePath) throws -> LocalizationCatalog {
        let url = appRoot(file: file).appendingPathComponent("Alike/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = (json as? [String: Any])?["strings"] as? [String: [String: Any]]
        return LocalizationCatalog(strings: try #require(strings))
    }

    /// The keys the wrapper resolves, read back out of the wrapper source.
    static func wrapperKeys(file: StaticString = #filePath) throws -> Set<String> {
        let url = appRoot(file: file)
            .appendingPathComponent("Alike/Localization/\(wrapperName).swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"(?:string|plural)\("([^"]+)"[,)]"#)
        let range = NSRange(source.startIndex..., in: source)
        return Set(pattern.matches(in: source, range: range).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        })
    }

    func localizations(of key: String) throws -> [String: [String: Any]] {
        let entry = try #require(strings[key], "missing key \(key)")
        return try #require(
            entry["localizations"] as? [String: [String: Any]],
            "no localizations for \(key)"
        )
    }
}

@Suite struct LocalizationCatalogTests {
    @Test func testEveryWrapperKeyExistsInTheCatalog() throws {
        let catalog = try LocalizationCatalog.load()
        let missing = try LocalizationCatalog.wrapperKeys().subtracting(catalog.strings.keys)

        #expect(
            missing.isEmpty,
            "wrapper resolves keys the catalog does not define: \(missing.sorted())"
        )
    }

    /// The reverse direction matters more here than in the packages: the app catalog is exactly
    /// where 103 keys with no call site accumulated, and this is what stops that recurring.
    @Test func testEveryCatalogKeyIsReachableThroughTheWrapper() throws {
        let catalog = try LocalizationCatalog.load()
        let unreachable = Set(catalog.strings.keys)
            .subtracting(try LocalizationCatalog.wrapperKeys())

        #expect(
            unreachable.isEmpty,
            "catalog keys no wrapper accessor resolves: \(unreachable.sorted())"
        )
    }

    /// A literal that never got a semantic key would land here as its own English text — which is
    /// how the app catalog filled up with copy nobody could translate against.
    @Test func testEveryKeyIsNamespacedToTheAppTarget() throws {
        let catalog = try LocalizationCatalog.load()
        let foreign = catalog.strings.keys.filter { !$0.hasPrefix(LocalizationCatalog.modulePrefix) }

        #expect(
            foreign.isEmpty,
            "keys outside the \(LocalizationCatalog.modulePrefix) namespace: \(foreign.sorted())"
        )
    }

    @Test func testEveryKeyCarriesEveryShippedLanguage() throws {
        let catalog = try LocalizationCatalog.load()
        var incomplete: [String] = []

        for key in catalog.strings.keys.sorted() {
            let localizations = try catalog.localizations(of: key)
            for language in LocalizationCatalog.shippedLanguages where localizations[language] == nil {
                incomplete.append("\(key) [\(language)]")
            }
        }

        #expect(incomplete.isEmpty, "incomplete entries: \(incomplete)")
    }
}
