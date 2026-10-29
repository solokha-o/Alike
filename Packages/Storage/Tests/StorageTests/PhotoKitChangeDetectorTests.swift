import Foundation
import Testing
@testable import Storage

@Suite struct PhotoKitChangeDetectorTests {
    @Test func testAccumulateAssetChangesUnionsInsertedAndDeletedIdentifiers() {
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

        #expect(result?.inserted == ["a", "b"])
        #expect(result?.deleted == ["c"])
    }

    /// A history record that fails to read must not collapse into "no
    /// changes": the failed record could be the only insertion or deletion,
    /// so the accumulator has to report "cannot answer" (nil) rather than
    /// silently skip it.
    @Test func testThrowingHistoryRecordReturnsNilInsteadOfSkippingIt() {
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

        #expect(result == nil)
    }
}
