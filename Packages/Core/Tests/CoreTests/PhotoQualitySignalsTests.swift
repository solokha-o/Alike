import XCTest
@testable import Core

final class PhotoQualitySignalsTests: XCTestCase {
    // MARK: - Rejected faces

    func testEmptyFacesWithoutRejectionsMeansNobodyWasInThePhoto() {
        let signals = PhotoQualitySignals(faceSignals: [], rejectedFaceCounts: .empty)

        XCTAssertFalse(signals.hasFaces)
        XCTAssertFalse(signals.hasOnlyRejectedFaces)
    }

    /// The whole point of the counts: this state and the one above used to be
    /// the same empty array, which is why a gate that rejected every real face
    /// stayed invisible in the exported signals.
    func testEmptyFacesWithRejectionsIsDistinguishableFromNobodyBeingThere() {
        let signals = PhotoQualitySignals(
            faceSignals: [],
            rejectedFaceCounts: FaceRejectionCounts(tooSmallInFrame: 3)
        )

        XCTAssertFalse(signals.hasFaces)
        XCTAssertTrue(signals.hasOnlyRejectedFaces)
        XCTAssertEqual(signals.rejectedFaceCounts?.total, 3)
    }

    func testAPhotoWithAMeasuredFaceIsNotReportedAsRejectedOnly() {
        let signals = PhotoQualitySignals(
            faceSignals: [Self.face()],
            rejectedFaceCounts: FaceRejectionCounts(tooSmallInFrame: 1)
        )

        XCTAssertTrue(signals.hasFaces)
        XCTAssertFalse(signals.hasOnlyRejectedFaces)
    }

    func testRejectionCountsAddPerReason() {
        let combined = FaceRejectionCounts(lowConfidence: 1, tooSmallInFrame: 2)
            + FaceRejectionCounts(insufficientResolution: 3, cropFailed: 4)

        XCTAssertEqual(combined.lowConfidence, 1)
        XCTAssertEqual(combined.tooSmallInFrame, 2)
        XCTAssertEqual(combined.insufficientResolution, 3)
        XCTAssertEqual(combined.cropFailed, 4)
        XCTAssertEqual(combined.total, 10)
        XCTAssertTrue(FaceRejectionCounts.empty.isEmpty)
    }

    // MARK: - Coding

    func testSignalsRoundTripThroughCoding() throws {
        let signals = PhotoQualitySignals(
            globalSharpness: 42,
            subjectSharpness: 37,
            faceSignals: [Self.face()],
            rejectedFaceCounts: FaceRejectionCounts(lowConfidence: 1, insufficientResolution: 2),
            pixelArea: 12_000_000
        )

        let decoded = try JSONDecoder().decode(
            PhotoQualitySignals.self,
            from: JSONEncoder().encode(signals)
        )

        XCTAssertEqual(decoded, signals)
    }

    /// `qualitySignalsData` is a `Codable` blob on disk with no migration
    /// engine behind it. Rows written before the reject counts and the
    /// face-source size existed must still decode, or a user updating the app
    /// loses every cached measurement to a decode failure instead of a version
    /// miss.
    func testPayloadWrittenBeforeTheRejectCountsStillDecodes() throws {
        let legacy = """
        {
          "globalSharpness": 21.5,
          "darkClippedFraction": 0.01,
          "brightClippedFraction": 0.02,
          "subjectLumaStdDev": 0.3,
          "noiseEstimate": 0.04,
          "faceSignals": [
            {
              "detectionConfidence": 0.95,
              "boxPixelSize": 120,
              "sharpness": 30,
              "isCroppedByFrame": false
            }
          ],
          "pixelArea": 12000000
        }
        """

        let decoded = try JSONDecoder().decode(
            PhotoQualitySignals.self,
            from: Data(legacy.utf8)
        )

        XCTAssertEqual(decoded.globalSharpness, 21.5)
        XCTAssertNil(decoded.rejectedFaceCounts)
        XCTAssertFalse(decoded.hasOnlyRejectedFaces)
        XCTAssertEqual(decoded.usableFaceSignals.count, 1)
        // Unknown, not zero: a pre-fix measurement cannot claim its face came
        // from any particular number of real pixels.
        XCTAssertNil(decoded.usableFaceSignals.first?.sourcePixelSize)
    }

    private static func face(sourcePixelSize: Double? = 96) -> FaceQualitySignal {
        FaceQualitySignal(
            detectionConfidence: 0.95,
            boxPixelSize: 40,
            sourcePixelSize: sourcePixelSize,
            sharpness: 30,
            hasClosedEyes: false,
            isCroppedByFrame: false
        )
    }
}
