import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Photo thumbnail aspect-ratio sizing")
struct PhotoThumbnailAspectRatioSizePolicyTests {
    @Test("A valid width produces two positive dimensions")
    func validWidth() {
        let size = PhotoThumbnailAspectRatioSizePolicy.size(
            proposedWidth: 240,
            proposedHeight: 0,
            fallback: .zero,
            aspectRatio: 1.5
        )

        #expect(size == CGSize(width: 240, height: 160))
        #expect(PhotoThumbnailAspectRatioSizePolicy.isRenderable(size))
    }

    @Test("A zero width can use a valid proposed height")
    func validHeightFallback() {
        let size = PhotoThumbnailAspectRatioSizePolicy.size(
            proposedWidth: 0,
            proposedHeight: 120,
            fallback: .zero,
            aspectRatio: 1.5
        )

        #expect(size == CGSize(width: 180, height: 120))
    }

    @Test("Invalid inputs never produce a mixed zero-dimension size")
    func invalidInputs() {
        let invalidRatioSize = PhotoThumbnailAspectRatioSizePolicy.size(
            proposedWidth: 240,
            proposedHeight: nil,
            fallback: .zero,
            aspectRatio: CGFloat.infinity
        )
        let zeroProposalSize = PhotoThumbnailAspectRatioSizePolicy.size(
            proposedWidth: 0,
            proposedHeight: 0,
            fallback: .zero,
            aspectRatio: 1
        )

        #expect(invalidRatioSize == .zero)
        #expect(zeroProposalSize == .zero)
        #expect(!PhotoThumbnailAspectRatioSizePolicy.isRenderable(CGSize(width: 1_125, height: 0)))
    }
}
