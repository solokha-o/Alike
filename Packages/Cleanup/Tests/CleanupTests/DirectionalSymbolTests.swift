import XCTest

/// RTL guard (task 45).
///
/// `chevron.left` and `arrow.right` name a physical direction, so in a right-to-left
/// interface they point the wrong way unless something mirrors them for us. The
/// direction-relative names — `chevron.backward`, `chevron.forward`,
/// `arrow.forward` — mirror by definition, which is why they are the only ones this
/// package is allowed to ship. Bidirectional glyphs such as `arrow.left.arrow.right`
/// read the same either way and are deliberately not covered.
final class DirectionalSymbolTests: XCTestCase {
    private static let bannedSymbols = [
        "chevron.left",
        "chevron.right",
        "arrow.left.circle",
        "arrow.right.circle",
        "arrow.left.square",
        "arrow.right.square"
    ]

    private static var sourcesRoot: URL {
        URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()  // Tests/CleanupTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources/Cleanup")
    }

    func testNoPhysicalDirectionSymbolsInSource() throws {
        let root = Self.sourcesRoot
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        )

        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for (offset, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                for symbol in Self.bannedSymbols where line.contains("\"\(symbol)") {
                    offenders.append("\(url.lastPathComponent):\(offset + 1): \(symbol)")
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            Physical-direction SF Symbols do not mirror in a right-to-left layout.
            Use chevron.backward / chevron.forward / arrow.backward.* / arrow.forward.* instead:
            \(offenders.joined(separator: "\n"))
            """
        )
    }
}
