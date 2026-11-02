import Core
import XCTest
@testable import Details

final class PhotoMetadataPresentationTests: XCTestCase {
    private func decimal(_ value: Double) -> String {
        value.formatted(.number.locale(.alikeFormatting))
    }

    func testMegapixelsKeepAtMostOneFractionDigit() {
        XCTAssertEqual(
            PhotoMetadataPresentation.megapixelsText(12.19),
            String(format: DetailsL10n.ClusterDetails.mp, decimal(12.2))
        )
    }

    func testWholeMegapixelsDropTheFraction() {
        XCTAssertEqual(
            PhotoMetadataPresentation.megapixelsText(12),
            String(format: DetailsL10n.ClusterDetails.mp, decimal(12))
        )
    }

    func testPhotoWithoutTraitsIsAPhoto() {
        XCTAssertEqual(PhotoMetadataPresentation.photoTypeText([]), DetailsL10n.ClusterDetails.photo)
    }

    func testEveryTraitHasItsOwnLabel() {
        let labels: [(PhotoTrait, String)] = [
            (.screenshot, DetailsL10n.ClusterDetails.screenshot),
            (.panorama, DetailsL10n.ClusterDetails.panorama),
            (.livePhoto, DetailsL10n.ClusterDetails.livePhoto),
            (.hdr, DetailsL10n.ClusterDetails.hdr),
            (.depthEffect, DetailsL10n.ClusterDetails.depthEffect)
        ]
        for (trait, label) in labels {
            XCTAssertEqual(PhotoMetadataPresentation.photoTypeText([trait]), label)
        }
    }

    func testTraitsKeepTheirOrderAndAreCommaSeparated() {
        XCTAssertEqual(
            PhotoMetadataPresentation.photoTypeText([.hdr, .screenshot]),
            "\(DetailsL10n.ClusterDetails.hdr), \(DetailsL10n.ClusterDetails.screenshot)"
        )
    }
}
