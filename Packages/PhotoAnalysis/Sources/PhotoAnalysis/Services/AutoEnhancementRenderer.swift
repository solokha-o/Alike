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
        /// The recipe as it is stored in the library's adjustment data: filter
        /// names and their numeric parameters, readable by a future version.
        let adjustment: PhotoEnhancementAdjustment
        /// The filters that produced `image`, ready to be replayed on another
        /// frame and reproduce this exact rendering.
        let recipe: AppliedRecipe
    }

    /// A rendering recipe holding the very filters that produced it.
    ///
    /// Rebuilding a filter from its name is not enough: `autoAdjustmentFilters`
    /// hands back private filters (`CIFaceBalance` among them) that
    /// `CIFilter(name:)` cannot recreate faithfully, and the replay would then
    /// silently drop a step. Each application copies the prototype instead.
    ///
    /// `@unchecked Sendable`: the prototypes are never mutated after they are
    /// captured, and copying them is serialized — `CIFilter` is not documented
    /// as thread-safe, and a Live Photo edit processes frames concurrently.
    struct AppliedRecipe: @unchecked Sendable {
        struct Step {
            let prototype: CIFilter
        }

        let steps: [Step]
        private let copyLock = NSLock()

        init(steps: [Step]) {
            self.steps = steps
        }

        /// One independent filter chain, safe to use on the calling thread.
        func makeFilterChain() -> [CIFilter] {
            copyLock.lock()
            defer { copyLock.unlock() }
            return steps.compactMap { $0.prototype.copy() as? CIFilter }
        }

        static let empty = AppliedRecipe(steps: [])
    }

    private enum Constants {
        /// Mild, detail-preserving sharpening; applied only to frames that are
        /// already sharp enough to deserve it.
        static let unsharpRadius: Double = 1.5
        static let unsharpIntensity: Double = 0.3
        static let jpegQuality: Double = 0.95
        /// Pixel format for the HEIF write. Named rather than inlined so the
        /// repo-wide "no unpinned formatting" guard is not tripped by a
        /// `format:` label that has nothing to do with locales.
        static let heifPixelFormat = CIFormat.RGBA8
    }

    private let context: CIContext

    init(context: CIContext = CIContext(options: [.useSoftwareRenderer: false])) {
        self.context = context
    }

    func render(_ image: CIImage, allowsSharpening: Bool = false) -> Output {
        var output = image
        var steps: [PhotoEnhancementAdjustment.Step] = []
        var recipeSteps: [AppliedRecipe.Step] = []

        // Apple's own auto adjustments: exposure, contrast, shadows, tone and
        // white balance, each already bounded by the analysis of this photo.
        let filters = image.autoAdjustmentFilters(options: [
            .enhance: true,
            .redEye: false,
            .level: false
        ])
        for filter in filters {
            let prototype = (filter.copy() as? CIFilter) ?? filter
            filter.setValue(output, forKey: kCIInputImageKey)
            guard let filtered = filter.outputImage else { continue }
            output = filtered
            steps.append(
                PhotoEnhancementAdjustment.Step(
                    filterName: filter.name,
                    parameters: numericParameters(of: filter)
                )
            )
            recipeSteps.append(AppliedRecipe.Step(prototype: prototype))
        }

        if allowsSharpening, let sharpened = unsharpMask(output) {
            output = sharpened.image
            steps.append(sharpened.step)
            recipeSteps.append(AppliedRecipe.Step(prototype: sharpened.prototype))
        }

        return Output(
            image: output,
            adjustment: PhotoEnhancementAdjustment(steps: steps),
            recipe: AppliedRecipe(steps: recipeSteps)
        )
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

    /// Writes the rendered image where the photo library expects it, in the
    /// format the destination asks for.
    ///
    /// The format is not cosmetic: Photos validates the rendered resource, and
    /// handing it JPEG bytes for a HEIC asset fails that validation with
    /// `PHPhotosErrorInvalidResource`. HEIF falls back to JPEG when the device
    /// cannot encode it.
    ///
    /// Never in the source's own colour space: iPhone HDR captures carry an
    /// HLG/PQ space that JPEG cannot represent and `writeJPEGRepresentation`
    /// rejects outright, which is invisible on synthetic test images and fatal
    /// on a real photo.
    func write(_ image: CIImage, to url: URL) throws {
        let normalizedImage = normalized(image)
        if Self.heifExtensions.contains(url.pathExtension.lowercased()) {
            do {
                try context.writeHEIFRepresentation(
                    of: normalizedImage,
                    to: url,
                    format: Constants.heifPixelFormat,
                    colorSpace: Self.outputColorSpace,
                    options: [
                        CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String):
                            Constants.jpegQuality
                    ]
                )
                return
            } catch {
                AppLog.photoKit.debug(
                    "\(AppLog.tag(.photokit, "HEIF write failed, falling back to JPEG: \(error.localizedDescription)"))"
                )
            }
        }

        try context.writeJPEGRepresentation(
            of: normalizedImage,
            to: url,
            colorSpace: Self.outputColorSpace,
            options: [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String):
                    Constants.jpegQuality
            ]
        )
    }

    /// Kept for the tests that pin the wide-gamut regression.
    func writeJPEG(_ image: CIImage, to url: URL) throws {
        try context.writeJPEGRepresentation(
            of: normalized(image),
            to: url,
            colorSpace: Self.outputColorSpace,
            options: [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String):
                    Constants.jpegQuality
            ]
        )
    }

    static let heifExtensions: Set<String> = ["heic", "heif"]

    static let outputColorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.displayP3)
        ?? CGColorSpaceCreateDeviceRGB()

    /// Moves the image back to the origin when a filter or an orientation fix
    /// shifted its extent; an infinite extent has nothing to write.
    func normalized(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.isInfinite == false else { return image }
        guard extent.origin != .zero else { return image }
        return image.transformed(
            by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
        )
    }

    /// Replays a recipe on another image.
    ///
    /// The auto-adjustment parameters are measured once on the still frame and
    /// then applied unchanged, which is what keeps every frame of a Live Photo
    /// graded exactly like its still. A fresh `CIFilter` is built per call, so
    /// frames can be processed concurrently without sharing filter state.
    func apply(_ recipe: AppliedRecipe, to image: CIImage) -> CIImage {
        var output = image
        for filter in recipe.makeFilterChain() {
            filter.setValue(output, forKey: kCIInputImageKey)
            guard let filtered = filter.outputImage else { continue }
            output = filtered
        }
        return output
    }

    private func unsharpMask(
        _ image: CIImage
    ) -> (image: CIImage, step: PhotoEnhancementAdjustment.Step, prototype: CIFilter)? {
        guard let filter = CIFilter(name: "CIUnsharpMask") else { return nil }
        filter.setValue(Constants.unsharpRadius, forKey: kCIInputRadiusKey)
        filter.setValue(Constants.unsharpIntensity, forKey: kCIInputIntensityKey)
        let prototype = (filter.copy() as? CIFilter) ?? filter
        filter.setValue(image, forKey: kCIInputImageKey)
        guard let output = filter.outputImage else { return nil }
        return (
            output,
            PhotoEnhancementAdjustment.Step(
                filterName: filter.name,
                parameters: [
                    kCIInputRadiusKey: Constants.unsharpRadius,
                    kCIInputIntensityKey: Constants.unsharpIntensity
                ]
            ),
            prototype
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
