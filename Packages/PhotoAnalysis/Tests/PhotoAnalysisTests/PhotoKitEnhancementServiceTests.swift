import Core
import CoreImage
import Foundation
import Photos
import XCTest
@testable import PhotoAnalysis

final class PhotoKitEnhancementServiceTests: XCTestCase {
    private let identifier = "photo-1"

    // MARK: - Apply

    func testApplyingWritesAlikeAdjustmentDataAndFlagsTheCachedScore() async throws {
        let library = FakePhotoLibrary()
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([makeScore()])
        let service = makeService(library: library, repository: repository)

        let adjustment = try await service.applyEnhancement(localIdentifier: identifier)

        let saved = await library.savedAdjustmentData
        XCTAssertNotNil(saved)
        let decoded = try JSONDecoder().decode(PhotoEnhancementAdjustment.self, from: try XCTUnwrap(saved))
        XCTAssertEqual(decoded.steps.map(\.filterName), adjustment.steps.map(\.filterName))

        let stored = try await repository.loadScores(localIdentifiers: [identifier])
        XCTAssertEqual(stored[identifier]?.isAlikeEnhanced, true)
        // The signals must stay the ones measured before the enhancement.
        XCTAssertEqual(stored[identifier]?.signals.globalSharpness ?? 0, 40, accuracy: 0.000_1)
    }

    func testApplyingMapsAnUnavailableOriginalToItsOwnError() async {
        let library = FakePhotoLibrary(originalError: PhotoEnhancementError.originalUnavailable)
        let service = makeService(library: library)

        await assertThrows(.originalUnavailable) {
            _ = try await service.applyEnhancement(localIdentifier: self.identifier)
        }
    }

    func testApplyingMapsASaveFailureToSaveFailed() async {
        struct WriteError: Error {}
        let library = FakePhotoLibrary(saveError: WriteError())
        let service = makeService(library: library)

        await assertThrows(.saveFailed) {
            _ = try await service.applyEnhancement(localIdentifier: self.identifier)
        }
    }

    func testApplyingIsRefusedWithLimitedAccess() async {
        let service = makeService(library: FakePhotoLibrary(), authorization: .limited)

        await assertThrows(.limitedAccessNotEditable) {
            _ = try await service.applyEnhancement(localIdentifier: self.identifier)
        }
    }

    func testApplyingIsRefusedWithoutAuthorization() async {
        let service = makeService(library: FakePhotoLibrary(), authorization: .denied)

        await assertThrows(.notAuthorized) {
            _ = try await service.applyEnhancement(localIdentifier: self.identifier)
        }
    }

    func testApplyingIsRefusedForAnAssetTheUserCannotEdit() async {
        let service = makeService(library: FakePhotoLibrary(isEditable: false))

        await assertThrows(.limitedAccessNotEditable) {
            _ = try await service.applyEnhancement(localIdentifier: self.identifier)
        }
    }

    // MARK: - Revert

    func testRevertingRestoresTheOriginalAndClearsTheEnhancedFlag() async throws {
        let library = FakePhotoLibrary(
            existingAdjustmentFormatIdentifier: PhotoEnhancementAdjustment.formatIdentifier
        )
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([makeScore(isAlikeEnhanced: true)])
        let service = makeService(library: library, repository: repository)

        try await service.revertToOriginal(localIdentifier: identifier)

        let didRevert = await library.didRevert
        XCTAssertTrue(didRevert)
        let stored = try await repository.loadScores(localIdentifiers: [identifier])
        XCTAssertEqual(stored[identifier]?.isAlikeEnhanced, false)
    }

    func testRevertingIsRefusedForAnEditMadeByAnotherApp() async {
        let library = FakePhotoLibrary(existingAdjustmentFormatIdentifier: "com.example.otherEditor")
        let service = makeService(library: library)

        await assertThrows(.notEnhancedByAlike) {
            try await service.revertToOriginal(localIdentifier: self.identifier)
        }

        let didRevert = await library.didRevert
        XCTAssertFalse(didRevert)
    }

    func testRevertingIsRefusedForAnUneditedPhoto() async {
        let service = makeService(library: FakePhotoLibrary())

        await assertThrows(.notEnhancedByAlike) {
            try await service.revertToOriginal(localIdentifier: self.identifier)
        }
    }

    // MARK: - Availability

    func testEnhancementIsUnavailableForANonEditableAsset() async {
        let service = makeService(library: FakePhotoLibrary(isEditable: false))

        let canEnhance = await service.canEnhance(localIdentifier: identifier)

        XCTAssertFalse(canEnhance)
    }

    func testEnhancementIsUnavailableForAMissingAsset() async {
        let service = makeService(library: FakePhotoLibrary(isMissing: true))

        let canEnhance = await service.canEnhance(localIdentifier: identifier)

        XCTAssertFalse(canEnhance)
    }

    func testOnlyAlikesOwnEditIsRecognizedAsEnhanced() async {
        let ours = makeService(library: FakePhotoLibrary(
            existingAdjustmentFormatIdentifier: PhotoEnhancementAdjustment.formatIdentifier
        ))
        let theirs = makeService(library: FakePhotoLibrary(
            existingAdjustmentFormatIdentifier: "com.example.otherEditor"
        ))

        let isOurs = await ours.isEnhancedByAlike(localIdentifier: identifier)
        let isTheirs = await theirs.isEnhancedByAlike(localIdentifier: identifier)

        XCTAssertTrue(isOurs)
        XCTAssertFalse(isTheirs)
    }

    // MARK: - Preview

    func testPreviewRendersWithoutTouchingTheLibrary() async throws {
        let library = FakePhotoLibrary()
        let service = makeService(library: library)

        let preview = try await service.renderPreview(
            localIdentifier: identifier,
            targetSize: CGSize(width: 64, height: 64)
        )

        XCTAssertLessThanOrEqual(preview.width, 64)
        let saved = await library.savedAdjustmentData
        XCTAssertNil(saved)
        let didRevert = await library.didRevert
        XCTAssertFalse(didRevert)
    }

    // MARK: - Helpers

    private func makeService(
        library: FakePhotoLibrary,
        authorization: PHAuthorizationStatus = .authorized,
        repository: (any PhotoQualityScoreRepository)? = nil
    ) -> PhotoKitEnhancementService {
        PhotoKitEnhancementService(
            authorizationStatusProvider: { authorization },
            requestBuilder: { _ in await library.makeRequest() },
            qualityScoreRepository: repository
        )
    }

    private func makeScore(isAlikeEnhanced: Bool = false) -> PhotoQualityScore {
        PhotoQualityScore(
            localIdentifier: identifier,
            sourceModificationDate: Date(timeIntervalSince1970: 100),
            scoringModelVersion: PhotoQualityScoringConfig.current.scoringModelVersion,
            thumbnailConfigVersion: PhotoQualityScoringConfig.current.thumbnailConfigVersion,
            signals: PhotoQualitySignals(globalSharpness: 40, subjectLumaStdDev: 0.2, pixelArea: 1_000),
            isAlikeEnhanced: isAlikeEnhanced
        )
    }

    private func assertThrows(
        _ expected: PhotoEnhancementError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as PhotoEnhancementError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

/// Stands in for the photo library: records what an edit would have written and
/// can fail on demand, so every error path is exercised without a real library.
private actor FakePhotoLibrary {
    private let isMissing: Bool
    private let isEditable: Bool
    private let existingAdjustmentFormatIdentifier: String?
    private let originalError: Error?
    private let saveError: Error?

    private(set) var savedAdjustmentData: Data?
    private(set) var didRevert = false

    init(
        isMissing: Bool = false,
        isEditable: Bool = true,
        existingAdjustmentFormatIdentifier: String? = nil,
        originalError: Error? = nil,
        saveError: Error? = nil
    ) {
        self.isMissing = isMissing
        self.isEditable = isEditable
        self.existingAdjustmentFormatIdentifier = existingAdjustmentFormatIdentifier
        self.originalError = originalError
        self.saveError = saveError
    }

    func makeRequest() -> ResolvedPhotoEnhancementRequest? {
        guard !isMissing else { return nil }
        return ResolvedPhotoEnhancementRequest(
            isEditable: isEditable,
            existingAdjustmentFormatIdentifier: existingAdjustmentFormatIdentifier,
            loadOriginal: { [self] in
                if let originalError = await self.originalError { throw originalError }
                return CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 256, height: 256))
            },
            saveEnhanced: { [self] _, adjustmentData in
                if let saveError = await self.saveError { throw saveError }
                await self.recordSave(adjustmentData)
            },
            revertToOriginal: { [self] in
                await self.recordRevert()
            }
        )
    }

    private func recordSave(_ adjustmentData: Data) {
        savedAdjustmentData = adjustmentData
    }

    private func recordRevert() {
        didRevert = true
    }
}
