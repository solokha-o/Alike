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
}
