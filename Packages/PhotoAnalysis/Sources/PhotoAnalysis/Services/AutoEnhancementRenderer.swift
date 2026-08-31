import Core
import CoreGraphics
import CoreImage
import Foundation

/// The fixed, conservative enhancement recipe.
///
/// It cleans up exposure and colour; it deliberately does **not** try to cure
/// blur, because auto-enhancement must never make a weak Best Shot merely look
/// acceptable.
struct AutoEnhancementRenderer: Sendable {
    struct Output {
        let image: CIImage
        let adjustment: PhotoEnhancementAdjustment
    }

    private enum Constants {
        /// Mild, detail-preserving sharpening; applied only to frames that are
        /// already sharp enough to deserve it.
        static let unsharpRadius: Double = 1.5
        static let unsharpIntensity: Double = 0.3
        static let jpegQuality: Double = 0.95
    }

    private let context: CIContext

    init(context: CIContext = CIContext(options: [.useSoftwareRenderer: false])) {
        self.context = context
    }

    func render(_ image: CIImage, allowsSharpening: Bool = false) -> Output {
        var output = image
        var steps: [PhotoEnhancementAdjustment.Step] = []

        // Apple's own auto adjustments: exposure, contrast, shadows, tone and
        // white balance, each already bounded by the analysis of this photo.
        let filters = image.autoAdjustmentFilters(options: [
            .enhance: true,
            .redEye: false,
            .level: false
        ])
        for filter in filters {
            filter.setValue(output, forKey: kCIInputImageKey)
            guard let filtered = filter.outputImage else { continue }
            output = filtered
            steps.append(
                PhotoEnhancementAdjustment.Step(
                    filterName: filter.name,
                    parameters: numericParameters(of: filter)
                )
            )
        }

        if allowsSharpening, let sharpened = unsharpMask(output) {
            output = sharpened.image
            steps.append(sharpened.step)
        }

        return Output(image: output, adjustment: PhotoEnhancementAdjustment(steps: steps))
    }

    /// Screen-sized preview. Nothing here touches the photo library.
    func makePreview(of image: CIImage, targetSize: CGSize) -> CGImage? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        guard targetSize.width > 0, targetSize.height > 0 else {
            return context.createCGImage(image, from: extent)
        }

        let scale = min(targetSize.width / extent.width, targetSize.height / extent.height, 1)
        let scaled = scale < 1
            ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : image
        return context.createCGImage(scaled, from: scaled.extent)
    }

    /// Writes the rendered image where the photo library expects it.
    func writeJPEG(_ image: CIImage, to url: URL) throws {
        try context.writeJPEGRepresentation(
            of: image,
            to: url,
            colorSpace: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            options: [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String):
                    Constants.jpegQuality
            ]
        )
    }

    private func unsharpMask(_ image: CIImage) -> (image: CIImage, step: PhotoEnhancementAdjustment.Step)? {
        guard let filter = CIFilter(name: "CIUnsharpMask") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(Constants.unsharpRadius, forKey: kCIInputRadiusKey)
        filter.setValue(Constants.unsharpIntensity, forKey: kCIInputIntensityKey)
        guard let output = filter.outputImage else { return nil }
        return (
            output,
            PhotoEnhancementAdjustment.Step(
                filterName: filter.name,
                parameters: [
                    kCIInputRadiusKey: Constants.unsharpRadius,
                    kCIInputIntensityKey: Constants.unsharpIntensity
                ]
            )
        )
    }

    /// Records the numeric inputs of a filter so the stored recipe describes
    /// what was actually applied, not just which filters ran.
    private func numericParameters(of filter: CIFilter) -> [String: Double] {
        var parameters: [String: Double] = [:]
        for key in filter.inputKeys where key != kCIInputImageKey {
            if let number = filter.value(forKey: key) as? NSNumber {
                parameters[key] = number.doubleValue
            }
        }
        return parameters
    }
}
