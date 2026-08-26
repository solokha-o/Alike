import XCTest

/// RTL guard (task 45).
///
/// `chevron.left`, `arrow.right` and `arrow.up.right.square` name a physical direction, so in a
/// right-to-left interface they point the wrong way unless something mirrors them for us. The
/// direction-relative names — `chevron.backward`, `chevron.forward`, `arrow.forward`,
/// `arrow.up.forward.square` — mirror by definition, which is why they are the only ones the
/// repository is allowed to ship.
///
/// Bidirectional glyphs are deliberately not covered: `arrow.left.arrow.right` and
/// `arrow.up.left.and.arrow.down.right` read the same either way. That is also why this matches
/// whole symbol names rather than prefixes — a prefix list built from `arrow.right.square` never
/// saw `arrow.up.right.square`, and a prefix list wide enough to catch it would have condemned
/// the resize glyph.
final class DirectionalSymbolTests: XCTestCase {
    private static let bannedSymbols: Set<String> = [
        "chevron.left", "chevron.right",
        "chevron.left.circle", "chevron.right.circle",
        "chevron.left.circle.fill", "chevron.right.circle.fill",
        "chevron.left.square", "chevron.right.square",
        "arrow.left", "arrow.right",
        "arrow.left.circle", "arrow.right.circle",
        "arrow.left.circle.fill", "arrow.right.circle.fill",
        "arrow.left.square", "arrow.right.square",
        "arrow.left.square.fill", "arrow.right.square.fill",
        "arrow.up.left", "arrow.up.right", "arrow.down.left", "arrow.down.right",
        "arrow.up.left.square", "arrow.up.right.square",
        "arrow.down.left.square", "arrow.down.right.square",
        "arrow.up.left.square.fill", "arrow.up.right.square.fill",
        "arrow.up.left.circle", "arrow.up.right.circle",
        "arrow.up.left.circle.fill", "arrow.up.right.circle.fill",
        "arrow.uturn.left", "arrow.uturn.right",
        "arrow.turn.up.left", "arrow.turn.up.right"
    ]

    private static let symbolLiteral = try! NSRegularExpression(pattern: "\"([a-z0-9.]+)\"")

    func testNoPhysicalDirectionSymbolsInAnyPackage() throws {
        var offenders: [String] = []

        for package in try Self.packageDirectories() {
            let sources = package.appendingPathComponent("Sources")
            guard FileManager.default.fileExists(atPath: sources.path) else { continue }
            let enumerator = try XCTUnwrap(
                FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
            )
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let source = try String(contentsOf: url, encoding: .utf8)
                for (offset, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    for name in Self.symbolNames(in: String(line)) where Self.bannedSymbols.contains(name) {
                        offenders.append("\(package.lastPathComponent)/\(url.lastPathComponent):\(offset + 1): \(name)")
                    }
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            Physical-direction SF Symbols do not mirror in a right-to-left layout. Use the \
            direction-relative twin instead — chevron.backward / chevron.forward / \
            arrow.backward.* / arrow.forward.* / arrow.up.forward.square:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    private static func symbolNames(in line: String) -> [String] {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return symbolLiteral.matches(in: line, range: range).compactMap { match in
            Range(match.range(at: 1), in: line).map { String(line[$0]) }
        }
    }

    private static func packageDirectories() throws -> [URL] {
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
