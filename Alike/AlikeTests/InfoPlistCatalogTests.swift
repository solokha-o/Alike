import XCTest

/// The permission prompts are the first sentence a new user reads, and they live outside
/// `Localizable.xcstrings`: the build setting `INFOPLIST_KEY_<key>` puts the English base value
/// into the generated `Info.plist`, and `Alike/Alike/InfoPlist.xcstrings` translates it.
///
/// Both halves are needed. Without the build setting the key is absent from `Info.plist`, the
/// catalog has nothing to localize and the permission request crashes; without the catalog the
/// prompt is English in every locale, which is how it shipped until task 46.
struct InfoPlistCatalog {
    static let appBundleIdentifier = "com.alike.app"

    let strings: [String: [String: Any]]

    static func load(file: StaticString = #filePath) throws -> InfoPlistCatalog {
        let url = LocalizationCatalog.appRoot(file: file)
            .appendingPathComponent("Alike/InfoPlist.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = (json as? [String: Any])?["strings"] as? [String: [String: Any]]
        return InfoPlistCatalog(strings: try XCTUnwrap(strings))
    }

    /// One entry per build configuration of the app target: its usage-description build settings,
    /// keyed by the `Info.plist` key they produce.
    static func appConfigurations(file: StaticString = #filePath) throws -> [[String: String]] {
        let url = LocalizationCatalog.appRoot(file: file)
            .appendingPathComponent("Alike.xcodeproj/project.pbxproj")
        let project = try String(contentsOf: url, encoding: .utf8)
        let setting = try NSRegularExpression(
            pattern: #"INFOPLIST_KEY_(NS\w+UsageDescription) = "((?:[^"\\]|\\.)*)";"#
        )

        return project.components(separatedBy: "isa = XCBuildConfiguration;")
            .filter { $0.contains("PRODUCT_BUNDLE_IDENTIFIER = \(appBundleIdentifier);") }
            .map { configuration in
                let range = NSRange(configuration.startIndex..., in: configuration)
                var settings: [String: String] = [:]
                for match in setting.matches(in: configuration, range: range) {
                    guard let key = Range(match.range(at: 1), in: configuration),
                          let value = Range(match.range(at: 2), in: configuration) else { continue }
                    settings[String(configuration[key])] = String(configuration[value])
                        .replacingOccurrences(of: #"\""#, with: #"""#)
                        .replacingOccurrences(of: #"\\"#, with: #"\"#)
                }
                return settings
            }
    }

    var usageDescriptionKeys: [String] {
        strings.keys.filter { $0.hasSuffix("UsageDescription") }.sorted()
    }

    func value(of key: String, in language: String) -> String? {
        let localizations = strings[key]?["localizations"] as? [String: [String: Any]]
        let unit = localizations?[language]?["stringUnit"] as? [String: Any]
        guard unit?["state"] as? String == "translated" else { return nil }
        return (unit?["value"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

final class InfoPlistCatalogTests: XCTestCase {
    func testTheAppTargetIsFoundInTheProject() throws {
        let configurations = try InfoPlistCatalog.appConfigurations()

        XCTAssertEqual(configurations.count, 2, "expected the Debug and Release configurations")
    }

    /// Guards the crash: the old task 46 card said to delete the build setting, and the catalog
    /// alone would leave `Info.plist` without a purpose string.
    func testEveryCatalogUsageDescriptionIsABuildSettingInEveryConfiguration() throws {
        let catalog = try InfoPlistCatalog.load()
        let configurations = try InfoPlistCatalog.appConfigurations()
        XCTAssertFalse(catalog.usageDescriptionKeys.isEmpty, "no usage description in the catalog")

        for (index, settings) in configurations.enumerated() {
            let missing = Set(catalog.usageDescriptionKeys).subtracting(settings.keys)
            XCTAssertTrue(
                missing.isEmpty,
                "configuration \(index) has no INFOPLIST_KEY_ build setting for \(missing.sorted())"
            )
        }
    }

    func testEveryUsageDescriptionBuildSettingIsInTheCatalog() throws {
        let catalog = try InfoPlistCatalog.load()
        let settingKeys = Set(try InfoPlistCatalog.appConfigurations().flatMap(\.keys))
        let missing = settingKeys.subtracting(catalog.strings.keys)

        XCTAssertTrue(missing.isEmpty, "build settings the catalog does not translate: \(missing.sorted())")
    }

    /// Translators work against the catalog's English, so it has to be the English that ships.
    func testTheCatalogEnglishMatchesTheBuildSetting() throws {
        let catalog = try InfoPlistCatalog.load()

        for settings in try InfoPlistCatalog.appConfigurations() {
            for (key, buildSetting) in settings {
                XCTAssertEqual(catalog.value(of: key, in: "en"), buildSetting, "\(key) drifted")
            }
        }
    }

    func testEveryUsageDescriptionCarriesEveryShippedLanguage() throws {
        let catalog = try InfoPlistCatalog.load()
        var incomplete: [String] = []

        for key in catalog.usageDescriptionKeys {
            for language in LocalizationCatalog.shippedLanguages
            where catalog.value(of: key, in: language) == nil {
                incomplete.append("\(key) [\(language)]")
            }
        }

        XCTAssertTrue(incomplete.isEmpty, "untranslated entries: \(incomplete)")
    }
}
