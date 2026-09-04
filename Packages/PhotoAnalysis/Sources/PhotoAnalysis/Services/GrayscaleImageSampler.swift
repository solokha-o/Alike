import CoreGraphics
import Foundation

/// A square grayscale sample of an image, shared by every measurement that
/// works on luma: sharpness, clipping, contrast and noise.
struct GrayscalePixels: Sendable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    subscript(_ x: Int, _ y: Int) -> UInt8 {
        bytes[(y * width) + x]
    }

    /// Luma in 0…1.
    func luma(_ x: Int, _ y: Int) -> Double {
        Double(self[x, y]) / 255.0
    }
}

enum GrayscaleImageSampler {
    /// Draws `image` into a `dimension × dimension` 8-bit gray context.
    ///
    /// The aspect ratio is not preserved: every measurement built on this is a
    /// comparison between photos of one cluster sampled exactly the same way.
    static func sample(_ image: CGImage, dimension: Int) -> GrayscalePixels? {
        guard dimension > 2 else { return nil }
        let bytesPerRow = dimension
        var data = [UInt8](repeating: 0, count: dimension * dimension)

        guard let context = CGContext(
            data: &data,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))
        return GrayscalePixels(width: dimension, height: dimension, bytes: data)
    }
}
