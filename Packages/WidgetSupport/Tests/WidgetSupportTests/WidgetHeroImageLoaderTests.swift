import CoreGraphics
import Foundation
import Testing
@testable import WidgetSupport

/// The loader exists for one reason — decoding a 1254 px scene at the ~90 pt it is drawn
/// at, instead of in full, inside an extension with a memory budget around 30 MB. A
/// regression here does not fail a build or look wrong; it just makes the widget get
/// killed on some device. So the bound is asserted rather than trusted.
@Suite("Widget hero image loader")
struct WidgetHeroImageLoaderTests {
    private func heroURL() throws -> URL {
        try #require(WidgetHeroAssets.url(for: .comparisonReview, scale: .threeX))
    }

    @Test("decodes no larger than the requested bound", arguments: [64, 128, 270])
    func honoursMaxPixelSize(maxPixelSize: Int) throws {
        let image = try #require(WidgetHeroImageLoader.cgImage(at: try heroURL(), maxPixelSize: maxPixelSize))
        #expect(max(image.width, image.height) <= maxPixelSize)
    }

    /// The whole point: the bound has to actually shrink the source, not silently hand
    /// back the full-size bitmap.
    @Test("decodes far smaller than the source")
    func downsamplesTheSource() throws {
        let image = try #require(WidgetHeroImageLoader.cgImage(at: try heroURL(), maxPixelSize: 270))
        #expect(max(image.width, image.height) < 1254)
    }

    @Test("nil for a missing file")
    func missingFile() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("no-such-hero.png")
        #expect(WidgetHeroImageLoader.cgImage(at: url, maxPixelSize: 128) == nil)
    }

    @Test("nil for a file that is not an image")
    func notAnImage() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("widget-hero-\(UUID().uuidString).png")
        try Data("not a png".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(WidgetHeroImageLoader.cgImage(at: url, maxPixelSize: 128) == nil)
    }

    @Test("nil for no url and for a non-positive bound")
    func degenerateInputs() throws {
        #expect(WidgetHeroImageLoader.cgImage(at: nil, maxPixelSize: 128) == nil)
        #expect(WidgetHeroImageLoader.cgImage(at: try heroURL(), maxPixelSize: 0) == nil)
    }

    @Test("pixel bound follows the display scale")
    func pixelBound() {
        #expect(WidgetHeroImageLoader.maxPixelSize(pointSize: 90, displayScale: 3) == 270)
        #expect(WidgetHeroImageLoader.maxPixelSize(pointSize: 90, displayScale: 2) == 180)
        // A scale of zero would otherwise collapse the bound and return no image at all.
        #expect(WidgetHeroImageLoader.maxPixelSize(pointSize: 90, displayScale: 0) == 90)
    }
}
