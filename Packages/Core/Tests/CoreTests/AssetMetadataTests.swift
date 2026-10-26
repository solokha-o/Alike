import Foundation
import Testing
import Photos
@testable import Core

@Suite struct AssetMetadataTests {
    @Test func testResolutionFormatting() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 400,
            pixelHeight: 300,
            isFavorite: false,
            mediaType: .image
        )

        #expect(metadata.resolution == "400 × 300")
    }

    @Test func testFormattedCreationDateUnknownWhenNil() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaType: .image
        )

        #expect(metadata.formattedCreationDate == "Unknown")
    }

    @Test func testFormattedCreationDateNotEmpty() {
        let metadata = AssetMetadata(
            creationDate: Date(timeIntervalSince1970: 0),
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaType: .image
        )

        #expect(!metadata.formattedCreationDate.isEmpty)
        #expect(metadata.formattedCreationDate != "Unknown")
    }

    @Test func testEstimatedCleanupBytesIsAvailableWithoutUIKit() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 400,
            pixelHeight: 300,
            isFavorite: false,
            mediaType: .image
        )

        #expect(metadata.estimatedCleanupBytes == 60_000)
    }

    @Test func testMegapixelCountUsesPixelDimensions() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 4_000,
            pixelHeight: 3_000,
            isFavorite: false,
            mediaType: .image
        )

        #expect(abs(metadata.megapixelCount - 12) <= 0.001)
    }

    @Test func testFormattedModificationDateIsNilWhenUnavailable() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaType: .image
        )

        #expect(metadata.formattedModificationDate == nil)
    }

    @Test func testFormattedModificationDateIsAvailable() throws {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: Date(timeIntervalSince1970: 0),
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaType: .image
        )

        let formattedModificationDate = try #require(metadata.formattedModificationDate)
        #expect(!formattedModificationDate.isEmpty)
    }

    @Test func testPhotoTraitsMapFromAssetMediaSubtypes() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaType: .image,
            mediaSubtypes: [.photoScreenshot, .photoPanorama, .photoLive, .photoHDR, .photoDepthEffect]
        )

        #expect(
            metadata.photoTraits == [.screenshot, .panorama, .livePhoto, .hdr, .depthEffect]
        )
    }

    @Test func testNewMetadataDefaultsRemainEmpty() {
        let metadata = AssetMetadata(
            creationDate: nil,
            modificationDate: nil,
            pixelWidth: 1,
            pixelHeight: 1,
            isFavorite: false,
            mediaType: .image
        )

        #expect(metadata.photoTraits.isEmpty)
        #expect(metadata.location == nil)
    }

    @Test func testLocationPreservesCoordinates() {
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

        #expect(metadata.location == location)
    }
}
