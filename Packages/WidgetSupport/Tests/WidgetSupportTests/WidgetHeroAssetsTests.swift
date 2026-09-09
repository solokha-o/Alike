import Foundation
import Testing
@testable import WidgetSupport

/// The hero artwork is a *copy* of three `DesignSystem` scenes, and a copy that nothing
/// checks is a copy that quietly goes missing: SwiftPM will happily build a bundle
/// without a PNG someone forgot to add, and the first sign of it is a widget with a
/// blank corner on a user's home screen. These read the bundle back.
@Suite("Widget hero assets")
struct WidgetHeroAssetsTests {
    @Test("every scene resolves at every scale", arguments: WidgetHeroScene.allCases, WidgetHeroScale.allCases)
    func sceneResolves(scene: WidgetHeroScene, scale: WidgetHeroScale) throws {
        let url = try #require(
            WidgetHeroAssets.url(for: scene, scale: scale),
            "no bundled artwork for \(scene) at \(scale)"
        )
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("each scale resolves its own file")
    func scalesAreDistinct() throws {
        for scene in WidgetHeroScene.allCases {
            let urls = WidgetHeroScale.allCases.compactMap { WidgetHeroAssets.url(for: scene, scale: $0) }
            #expect(Set(urls).count == WidgetHeroScale.allCases.count, "\(scene) collapses two scales onto one file")
        }
    }

    /// The @2x/@3x fallback in `url(for:scale:)` would hand back the @1x file if the
    /// larger export were missing, which is exactly the silent degradation this catches.
    @Test("the filename carries the scale suffix")
    func suffixIsApplied() throws {
        let twoX = try #require(WidgetHeroAssets.url(for: .comparisonReview, scale: .twoX))
        let threeX = try #require(WidgetHeroAssets.url(for: .comparisonReview, scale: .threeX))
        #expect(twoX.lastPathComponent == "AlikeComparisonReview@2x.png")
        #expect(threeX.lastPathComponent == "AlikeComparisonReview@3x.png")
    }

    /// Lottie never plays in WidgetKit and `DesignSystem` is deliberately not linked, so
    /// an overlay in this bundle would be pure weight against the extension's memory
    /// budget — and a sign someone copied a scene directory wholesale.
    @Test("no Lottie overlays travelled with the artwork")
    func noOverlaysShipped() throws {
        let root = try #require(Bundle.module.resourceURL)
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let overlays = enumerator.compactMap { $0 as? URL }.filter { $0.lastPathComponent.hasSuffix("Overlay.json") }
        #expect(overlays.isEmpty, "overlays in the widget bundle: \(overlays.map(\.lastPathComponent))")
    }

    @Test(
        "display scale picks the export",
        arguments: [
            (CGFloat(1.0), WidgetHeroScale.oneX),
            (1.49, .oneX),
            (2.0, .twoX),
            (2.49, .twoX),
            (2.5, .threeX),
            (3.0, .threeX)
        ]
    )
    func scaleFromDisplayScale(displayScale: CGFloat, expected: WidgetHeroScale) {
        #expect(WidgetHeroScale(displayScale: displayScale) == expected)
    }
}
