import Foundation
import Testing
@testable import WidgetSupport

/// The widget extension has its own bundle and cannot see the app's `AccentColor`,
/// and it deliberately does not link `DesignSystem`, so the accent is duplicated as a
/// named color inside this package. Duplication that nothing checks is duplication that
/// drifts: these tests read all three sources off disk and fail when they disagree,
/// so a palette change shows up as a red test rather than as a widget that is a
/// slightly different teal from the app it sits next to.
@Suite("Widget accent palette")
struct WidgetPaletteTests {
    private struct Components: Equatable, CustomStringConvertible {
        let red: Double, green: Double, blue: Double, alpha: Double
        var description: String { "(\(red), \(green), \(blue), \(alpha))" }
    }

    /// `<package>/../..` — the repository root. The two files this compares against
    /// live outside the package, which is the whole point of the comparison.
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WidgetSupportTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // WidgetSupport
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repository root
    }

    private func components(
        fromColorsetAt url: URL,
        darkAppearance: Bool
    ) throws -> Components {
        let json = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        let colors = try #require((json as? [String: Any])?["colors"] as? [[String: Any]])
        let entry = try #require(colors.first { color in
            let appearances = (color["appearances"] as? [[String: Any]]) ?? []
            let isDark = appearances.contains { ($0["value"] as? String) == "dark" }
            return isDark == darkAppearance
        }, "no \(darkAppearance ? "dark" : "light") entry in \(url.lastPathComponent)")
        let raw = try #require((entry["color"] as? [String: Any])?["components"] as? [String: String])
        func value(_ key: String) throws -> Double {
            let text = try #require(raw[key], "\(url.lastPathComponent) has no \(key) component")
            return try #require(Double(text))
        }
        return Components(
            red: try value("red"),
            green: try value("green"),
            blue: try value("blue"),
            alpha: try value("alpha")
        )
    }

    private var widgetAccentURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/WidgetSupport/Resources/WidgetAssets.xcassets/WidgetAccent.colorset/Contents.json"
            )
    }

    private var appAccentURL: URL {
        Self.repositoryRoot.appendingPathComponent(
            "Alike/Alike/Assets.xcassets/AccentColor.colorset/Contents.json"
        )
    }

    @Test("The widget's light accent matches the app's light accent")
    func lightMatchesApp() throws {
        #expect(
            try components(fromColorsetAt: widgetAccentURL, darkAppearance: false)
                == components(fromColorsetAt: appAccentURL, darkAppearance: false)
        )
    }

    @Test("The widget's dark accent matches the app's dark accent")
    func darkMatchesApp() throws {
        // The reason `Color.accent` from `Theme.swift` is not reused: it is flat, so
        // in dark mode a widget built on it would visibly disagree with the app.
        #expect(
            try components(fromColorsetAt: widgetAccentURL, darkAppearance: true)
                == components(fromColorsetAt: appAccentURL, darkAppearance: true)
        )
    }

    @Test("The widget's light accent matches DesignSystem's coded Color.accent")
    func lightMatchesTheme() throws {
        let theme = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "Packages/DesignSystem/Sources/DesignSystem/Theme.swift"
            ),
            encoding: .utf8
        )
        // `static let accent = Color(red: 0.12, green: 0.62, blue: 0.72)`
        let pattern = #"accent\s*=\s*Color\(\s*red:\s*([0-9.]+),\s*green:\s*([0-9.]+),\s*blue:\s*([0-9.]+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let match = try #require(
            regex.firstMatch(in: theme, range: NSRange(theme.startIndex..., in: theme)),
            "Color.accent is no longer declared as literal RGB in Theme.swift"
        )
        func value(_ index: Int) throws -> Double {
            let range = try #require(Range(match.range(at: index), in: theme))
            return try #require(Double(theme[range]))
        }

        let widget = try components(fromColorsetAt: widgetAccentURL, darkAppearance: false)
        #expect(widget.red == (try value(1)))
        #expect(widget.green == (try value(2)))
        #expect(widget.blue == (try value(3)))
        #expect(widget.alpha == 1)
    }
}
