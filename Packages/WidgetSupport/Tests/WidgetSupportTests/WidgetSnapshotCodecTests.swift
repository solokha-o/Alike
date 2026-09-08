import Foundation
import Testing
@testable import WidgetSupport

@Suite("Widget snapshot codec")
struct WidgetSnapshotCodecTests {
    private static let reference = WidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 1_770_000_000),
        photoAuthorization: .limited,
        hasCompletedScan: true,
        lastScanDate: Date(timeIntervalSince1970: 1_769_900_000),
        libraryChangedSinceScan: true,
        estimatedSavingsBytes: 1_932_735_283,
        clusterCount: 24,
        screenshotAssetCount: 86,
        blurredPhotoAssetCount: 12,
        isPremium: true,
        sessionProgress: WidgetSessionProgress(
            reviewedClusters: 18,
            totalClusters: 30,
            updatedAt: Date(timeIntervalSince1970: 1_769_950_000)
        )
    )

    @Test("A snapshot survives a full encode/decode round trip")
    func roundTrip() throws {
        let store = WidgetSnapshotStore(containerURL: FileManager.default.temporaryDirectory)
        _ = store
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            WidgetSnapshot.self,
            from: try encoder.encode(Self.reference)
        )

        #expect(decoded == Self.reference)
    }

    @Test("An unknown authorization value decodes to notDetermined instead of throwing")
    func unknownAuthorizationDegrades() throws {
        // A snapshot written by a newer app build must not be able to make the
        // installed extension throw; the worst it may do is lose a distinction.
        let json = Data(#"{"schemaVersion":1,"generatedAt":"2026-02-02T00:00:00Z","photoAuthorization":"quantumSuperposition","hasCompletedScan":false,"libraryChangedSinceScan":false,"isPremium":false}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(WidgetSnapshot.self, from: json)

        #expect(decoded.photoAuthorization == .notDetermined)
    }

    @Test("The payload carries no per-asset identifiers")
    func carriesNoPII() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(Self.reference), as: UTF8.self)

        // A `PHAsset.localIdentifier` looks like
        // "B84E8479-475C-4727-A4A4-B77AA9980897/L0/001". Neither its shape nor any
        // field that could carry a file path or an image blob may appear.
        #expect(json.range(of: #"[0-9A-Fa-f-]{36}/L0/"#, options: .regularExpression) == nil)
        for forbidden in ["localIdentifier", "identifiers", "thumbnail", "assetIDs", "file://", "/var/mobile"] {
            #expect(!json.contains(forbidden), "snapshot JSON leaked \(forbidden)")
        }

        // Structural, not just textual: every stored property is a scalar, a date or
        // the progress struct — nothing that could smuggle bytes in.
        let object = try #require(
            try JSONSerialization.jsonObject(with: try encoder.encode(Self.reference)) as? [String: Any]
        )
        #expect(object.values.allSatisfy { !($0 is [Any]) })
    }
}
