import Core
import Foundation

/// The rows of the photo info sheet that need more than a stored value.
enum PhotoMetadataPresentation {
    static func megapixelsText(_ megapixelCount: Double) -> String {
        let value = megapixelCount.formatted(
            FloatingPointFormatStyle<Double>.alikeDecimal.precision(.fractionLength(0...1))
        )
        return String(format: DetailsL10n.ClusterDetails.mp, value)
    }

    static func photoTypeText(_ photoTraits: [PhotoTrait]) -> String {
        guard !photoTraits.isEmpty else {
            return DetailsL10n.ClusterDetails.photo
        }

        return photoTraits.map { trait in
            switch trait {
            case .screenshot:
                DetailsL10n.ClusterDetails.screenshot
            case .panorama:
                DetailsL10n.ClusterDetails.panorama
            case .livePhoto:
                DetailsL10n.ClusterDetails.livePhoto
            case .hdr:
                DetailsL10n.ClusterDetails.hdr
            case .depthEffect:
                DetailsL10n.ClusterDetails.depthEffect
            }
        }
        .joined(separator: ", ")
    }
}
