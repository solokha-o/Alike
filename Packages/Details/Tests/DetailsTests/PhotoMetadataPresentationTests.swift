import Core
import Foundation
import Testing
@testable import Details

@Suite struct PhotoMetadataPresentationTests {
    private func decimal(_ value: Double) -> String {
        value.formatted(.number.locale(.alikeFormatting))
    }

    @Test func testMegapixelsKeepAtMostOneFractionDigit() {
        #expect(PhotoMetadataPresentation.megapixelsText(12.19) == String(format: DetailsL10n.ClusterDetails.mp, decimal(12.2)))
    }

    @Test func testWholeMegapixelsDropTheFraction() {
        #expect(PhotoMetadataPresentation.megapixelsText(12) == String(format: DetailsL10n.ClusterDetails.mp, decimal(12)))
    }

    @Test func testPhotoWithoutTraitsIsAPhoto() {
        #expect(PhotoMetadataPresentation.photoTypeText([]) == DetailsL10n.ClusterDetails.photo)
    }

    @Test func testEveryTraitHasItsOwnLabel() {
        let labels: [(PhotoTrait, String)] = [
            (.screenshot, DetailsL10n.ClusterDetails.screenshot),
            (.panorama, DetailsL10n.ClusterDetails.panorama),
            (.livePhoto, DetailsL10n.ClusterDetails.livePhoto),
            (.hdr, DetailsL10n.ClusterDetails.hdr),
            (.depthEffect, DetailsL10n.ClusterDetails.depthEffect)
        ]
        for (trait, label) in labels {
            #expect(PhotoMetadataPresentation.photoTypeText([trait]) == label)
        }
    }

    @Test func testTraitsKeepTheirOrderAndAreCommaSeparated() {
        #expect(PhotoMetadataPresentation.photoTypeText([.hdr, .screenshot]) == "\(DetailsL10n.ClusterDetails.hdr), \(DetailsL10n.ClusterDetails.screenshot)")
    }
}
