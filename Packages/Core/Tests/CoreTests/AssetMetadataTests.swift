import XCTest
import Photos
@testable import Core

final class AssetMetadataTests: XCTestCase {
    func testResolutionFormatting() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 400,
            pixelHeight: 300,
            isFavorite: false,
            mediaType: .image
        )

        XCTAssertEqual(metadata.resolution, "400 × 300")
    }

    func testFormattedCreationDateUnknownWhenNil() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaType: .image
        )

        XCTAssertEqual(metadata.formattedCreationDate, "Unknown")
    }

    func testFormattedCreationDateNotEmpty() {
        let metadata = AssetMetadata(
            creationDate: Date(timeIntervalSince1970: 0),
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaType: .image
        )

        XCTAssertFalse(metadata.formattedCreationDate.isEmpty)
        XCTAssertNotEqual(metadata.formattedCreationDate, "Unknown")
    }

    func testEstimatedCleanupBytesIsAvailableWithoutUIKit() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 400,
            pixelHeight: 300,
            isFavorite: false,
            mediaType: .image
        )

        XCTAssertEqual(metadata.estimatedCleanupBytes, 60_000)
    }

    func testMegapixelCountUsesPixelDimensions() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 4_000,
            pixelHeight: 3_000,
            isFavorite: false,
            mediaType: .image
        )

        XCTAssertEqual(metadata.megapixelCount, 12, accuracy: 0.001)
    }

    func testFormattedModificationDateIsNilWhenUnavailable() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaType: .image
        )

        XCTAssertNil(metadata.formattedModificationDate)
    }

    func testFormattedModificationDateIsAvailable() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: Date(timeIntervalSince1970: 0),
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaType: .image
        )

        XCTAssertFalse(try XCTUnwrap(metadata.formattedModificationDate).isEmpty)
    }

    func testPhotoTraitsMapFromAssetMediaSubtypes() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaType: .image,
            mediaSubtypes: [.photoScreenshot, .photoPanorama, .photoLive, .photoHDR, .photoDepthEffect]
        )

        XCTAssertEqual(
            metadata.photoTraits,
            [.screenshot, .panorama, .livePhoto, .hdr, .depthEffect]
        )
    }

    func testNewMetadataDefaultsRemainEmpty() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaType: .image
        )

        XCTAssertTrue(metadata.photoTraits.isEmpty)
        XCTAssertNil(metadata.location)
    }

    func testLocationPreservesCoordinates() {
        let location = AssetLocation(latitude: 50.4501, longitude: 30.5234)
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaType: .image,
            location: location
        )

        XCTAssertEqual(metadata.location, location)
    }
}
