import XCTest
@testable import Storage

final class PhotoKitChangeDetectorTests: XCTestCase {
    func testAccumulateAssetChangesUnionsInsertedAndDeletedIdentifiers() {
        let providers: [() throws -> PhotoKitChangeDetector.AssetChangeDetails] = [
            {
                PhotoKitChangeDetector.AssetChangeDetails(
                    insertedLocalIdentifiers: ["a"],
                    deletedLocalIdentifiers: []
                )
            },
            {
                PhotoKitChangeDetector.AssetChangeDetails(
                    insertedLocalIdentifiers: ["b"],
                    deletedLocalIdentifiers: ["c"]
                )
            },
        ]

        let result = PhotoKitChangeDetector.accumulateAssetChanges(providers)

        XCTAssertEqual(result?.inserted, ["a", "b"])
        XCTAssertEqual(result?.deleted, ["c"])
    }

    /// A history record that fails to read must not collapse into "no
    /// changes": the failed record could be the only insertion or deletion,
    /// so the accumulator has to report "cannot answer" (nil) rather than
    /// silently skip it.
    func testThrowingHistoryRecordReturnsNilInsteadOfSkippingIt() {
        struct RecordReadFailure: Error {}

        let providers: [() throws -> PhotoKitChangeDetector.AssetChangeDetails] = [
            {
                PhotoKitChangeDetector.AssetChangeDetails(
                    insertedLocalIdentifiers: ["a"],
                    deletedLocalIdentifiers: []
                )
            },
            { throw RecordReadFailure() },
        ]

        let result = PhotoKitChangeDetector.accumulateAssetChanges(providers)

        XCTAssertNil(result)
    }
}
