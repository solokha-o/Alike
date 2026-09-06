import Core
import CoreGraphics
import CoreImage
import ImageIO
import Foundation
import XCTest
@testable import PhotoAnalysis

final class AutoEnhancementRendererTests: XCTestCase {
    private let renderer = AutoEnhancementRenderer()
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("auto-enhancement-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    /// The regression this whole fix exists for: an image tagged with a wide
    /// colour space must still be writable as JPEG. Writing in the source's own
    /// space is what failed on a real iPhone photo.
    func testWritesJPEGForAWideGamutTaggedImage() throws {
        let displayP3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let image = makeImage(colorSpace: displayP3)
        let url = temporaryDirectory.appendingPathComponent("wide-gamut.jpg")

        try renderer.writeJPEG(image, to: url)

        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        XCTAssertGreaterThan(size ?? 0, 0)
    }

    func testWritesJPEGForAnImageWhoseExtentMoved() throws {
        let image = makeImage()
            .transformed(by: CGAffineTransform(translationX: 120, y: 80))
        let url = temporaryDirectory.appendingPathComponent("translated.jpg")

        XCTAssertNotEqual(image.extent.origin, .zero)
        try renderer.writeJPEG(image, to: url)

        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        XCTAssertGreaterThan(size ?? 0, 0)
    }

    /// Photos validates the rendered resource against the asset: JPEG bytes for
    /// a HEIC asset come back as `PHPhotosErrorInvalidResource`.
    func testWritesHEIFWhenTheDestinationIsHEIC() throws {
        let url = temporaryDirectory.appendingPathComponent("rendered.heic")

        try renderer.write(makeImage(), to: url)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let type = try XCTUnwrap(CGImageSourceGetType(source) as String?)
        XCTAssertTrue(type.contains("heic") || type.contains("heif"), "Unexpected type: \(type)")
    }

    func testWritesJPEGForEveryOtherDestination() throws {
        let url = temporaryDirectory.appendingPathComponent("rendered.jpg")

        try renderer.write(makeImage(), to: url)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let type = try XCTUnwrap(CGImageSourceGetType(source) as String?)
        XCTAssertTrue(type.contains("jpeg"), "Unexpected type: \(type)")
    }

    func testNormalizingMovesTheExtentBackToTheOrigin() {
        let moved = makeImage().transformed(by: CGAffineTransform(translationX: 40, y: -25))

        let normalized = renderer.normalized(moved)

        XCTAssertEqual(normalized.extent.origin, .zero)
        XCTAssertEqual(normalized.extent.size, moved.extent.size)
    }

    /// Live Photos replay the recipe on every video frame; if the replay did not
    /// reproduce the still exactly, the motion would be graded differently from
    /// the photo it belongs to.
    func testReplayingTheRecipeReproducesTheRenderedStill() throws {
        let image = makeImage()
        let rendered = renderer.render(image, allowsSharpening: true)

        let replayed = renderer.apply(rendered.recipe, to: image)

        let renderedPixels = try pixels(of: rendered.image)
        let replayedPixels = try pixels(of: replayed)
        // Core Image may fuse two equivalent graphs slightly differently, so
        // the bar is "visually identical", not bit-identical.
        XCTAssertLessThanOrEqual(maximumDifference(renderedPixels, replayedPixels), 2)
    }

    func testReplayingAnEmptyRecipeLeavesTheImageAlone() throws {
        let image = makeImage()

        let replayed = renderer.apply(.empty, to: image)

        XCTAssertEqual(try pixels(of: replayed), try pixels(of: image))
    }

    /// Guards the comparison above: an unapplied recipe must not pass as a
    /// replay of the rendered still.
    func testTheUnenhancedImageIsNotMistakenForTheRenderedOne() throws {
        let image = makeImage()
        let rendered = renderer.render(image, allowsSharpening: true)

        let difference = maximumDifference(try pixels(of: rendered.image), try pixels(of: image))

        XCTAssertGreaterThan(difference, 2)
    }

    func testPreviewIsScaledToFitTheRequestedSize() throws {
        let preview = try XCTUnwrap(
            renderer.makePreview(of: makeImage(), targetSize: CGSize(width: 64, height: 64))
        )

        XCTAssertLessThanOrEqual(preview.width, 64)
        XCTAssertLessThanOrEqual(preview.height, 64)
    }

    // MARK: - Helpers

    /// A small gradient with a few blocks, so the auto adjustments actually find
    /// something to correct.
    private func makeImage(
        side: Int = 256,
        colorSpace: CGColorSpace? = nil
    ) -> CIImage {
        let bytesPerPixel = 4
        let bytesPerRow = side * bytesPerPixel
        var data = [UInt8](repeating: 0, count: side * side * bytesPerPixel)

        for y in 0..<side {
            for x in 0..<side {
                let index = (y * bytesPerRow) + (x * bytesPerPixel)
                data[index] = UInt8(x * 255 / max(side - 1, 1))
                data[index + 1] = UInt8(y * 255 / max(side - 1, 1))
                data[index + 2] = (x / 16 + y / 16).isMultiple(of: 2) ? 40 : 200
                data[index + 3] = 255
            }
        }

        let space = colorSpace ?? CGColorSpaceCreateDeviceRGB()
        return CIImage(
            bitmapData: Data(data),
            bytesPerRow: bytesPerRow,
            size: CGSize(width: side, height: side),
            format: .RGBA8,
            colorSpace: space
        )
    }

    private func maximumDifference(_ lhs: Data, _ rhs: Data) -> Int {
        guard lhs.count == rhs.count else { return .max }
        return zip(lhs, rhs).reduce(0) { partial, pair in
            max(partial, abs(Int(pair.0) - Int(pair.1)))
        }
    }

    private func pixels(of image: CIImage) throws -> Data {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let normalized = renderer.normalized(image)
        let cgImage = try XCTUnwrap(context.createCGImage(normalized, from: normalized.extent))
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let bitmapContext = try XCTUnwrap(
            CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Data(bytes)
    }
}
