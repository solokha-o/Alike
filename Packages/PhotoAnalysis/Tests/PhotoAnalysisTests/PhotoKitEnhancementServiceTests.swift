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

    /// Layering our rendering on top of another app's adjustment is what Photos
    /// rejects, so the foreign edit is cleared through the library's own undo
    /// first — with the user's consent already given on the preview screen.
    func testReplacingAForeignEditRevertsItBeforeWriting() async throws {
        let library = FakePhotoLibrary(existingAdjustmentFormatIdentifier: "com.example.otherEditor")
        let service = makeService(library: library)

        _ = try await service.applyEnhancement(
            localIdentifier: identifier,
            replacingOtherEdits: true
        )

        let didRevert = await library.didRevert
        let saved = await library.savedAdjustmentData
        XCTAssertTrue(didRevert)
        XCTAssertNotNil(saved)
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

    func testApplyingPassesTheRenderedRecipeToTheSaveStep() async throws {
        let library = FakePhotoLibrary()
        let service = makeService(library: library)

        let adjustment = try await service.applyEnhancement(localIdentifier: identifier)

        // The recipe replayed on a Live Photo's frames must describe the same
        // steps that were stamped into the adjustment data.
        let recipeStepCount = await library.savedRecipeStepCount
        XCTAssertEqual(recipeStepCount, adjustment.steps.count)
    }

    func testAnUnsupportedAssetIsRefusedBeforeAnythingIsWritten() async {
        let library = FakePhotoLibrary(isSupported: false)
        let service = makeService(library: library)

        await assertThrows(.unsupportedAsset) {
            _ = try await service.applyEnhancement(localIdentifier: self.identifier)
        }

        let saved = await library.savedAdjustmentData
        XCTAssertNil(saved)
    }

    // MARK: - Availability

    func testEnhancementIsUnavailableForAnUnsupportedAsset() async {
        let service = makeService(library: FakePhotoLibrary(isSupported: false))

        let availability = await service.availability(localIdentifier: identifier)

        XCTAssertEqual(availability, .unavailable)
    }

    func testEnhancementIsUnavailableForANonEditableAsset() async {
        let service = makeService(library: FakePhotoLibrary(isEditable: false))

        let availability = await service.availability(localIdentifier: identifier)

        XCTAssertEqual(availability, .unavailable)
    }

    func testEnhancementIsUnavailableForAMissingAsset() async {
        let service = makeService(library: FakePhotoLibrary(isMissing: true))

        let availability = await service.availability(localIdentifier: identifier)

        XCTAssertEqual(availability, .unavailable)
    }

    func testAvailabilityIsAnsweredWithOneCheapResolution() async {
        let library = FakePhotoLibrary()
        let service = makeService(library: library)

        _ = await service.availability(localIdentifier: identifier)

        // Asking twice would resolve the photo twice, and resolving can pull a
        // full-size original down from iCloud.
        let purposes = await library.requestedPurposes
        XCTAssertEqual(purposes, [.availability])
    }

    func testOnlyAlikesOwnEditIsRecognizedAsEnhanced() async {
        let ours = makeService(library: FakePhotoLibrary(
            existingAdjustmentFormatIdentifier: PhotoEnhancementAdjustment.formatIdentifier
        ))
        let theirs = makeService(library: FakePhotoLibrary(
            existingAdjustmentFormatIdentifier: "com.example.otherEditor"
        ))
        let untouched = makeService(library: FakePhotoLibrary())

        let oursAvailability = await ours.availability(localIdentifier: identifier)
        let theirsAvailability = await theirs.availability(localIdentifier: identifier)
        let untouchedAvailability = await untouched.availability(localIdentifier: identifier)

        XCTAssertEqual(oursAvailability, .enhanced)
        // Another app's edit is not ours to replace silently — the action stays
        // available, and the UI says what applying it would do.
        XCTAssertEqual(theirsAvailability, .editedElsewhere)
        XCTAssertEqual(untouchedAvailability, .available)
    }

    func testApplyingRefusesToReplaceAnotherAppsEditWithoutConsent() async {
        let library = FakePhotoLibrary(existingAdjustmentFormatIdentifier: "com.example.otherEditor")
        let service = makeService(library: library)

        await assertThrows(.editedInAnotherApp) {
            _ = try await service.applyEnhancement(localIdentifier: self.identifier)
        }

        let saved = await library.savedAdjustmentData
        XCTAssertNil(saved)
    }

    func testApplyingReplacesAnotherAppsEditOnceTheUserAgrees() async throws {
        let library = FakePhotoLibrary(existingAdjustmentFormatIdentifier: "com.example.otherEditor")
        let service = makeService(library: library)

        _ = try await service.applyEnhancement(
            localIdentifier: identifier,
            replacingOtherEdits: true
        )

        let saved = await library.savedAdjustmentData
        XCTAssertNotNil(saved)
    }

    func testRevertingWorksForAnAssetAlikeCanNoLongerEnhance() async throws {
        // The Live Photo's video part is gone, so the asset is unsupported for
        // rendering — but putting the original back needs no rendering at all.
        let library = FakePhotoLibrary(
            isSupported: false,
            existingAdjustmentFormatIdentifier: PhotoEnhancementAdjustment.formatIdentifier
        )
        let service = makeService(library: library)

        try await service.revertToOriginal(localIdentifier: identifier)

        let didRevert = await library.didRevert
        XCTAssertTrue(didRevert)
    }

    func testApplyingCachesThePreEnhancementSignalsWhenNothingWasScored() async throws {
        let repository = MockPhotoQualityScoreRepository()
        let service = makeService(library: FakePhotoLibrary(), repository: repository)

        _ = try await service.applyEnhancement(localIdentifier: identifier)

        let stored = try await repository.loadScores(localIdentifiers: [identifier])
        let score = try XCTUnwrap(stored[identifier])
        XCTAssertTrue(score.isAlikeEnhanced)
        XCTAssertNil(score.signals.analysisFailure)
    }

    /// Another app replacing our edit must clear the cached marker, or the
    /// score cache keeps serving pre-edit signals for a photo that no longer
    /// carries Alike's enhancement.
    func testAForeignEditClearsTheCachedAlikeMarker() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([makeScore(isAlikeEnhanced: true)])
        let service = makeService(
            library: FakePhotoLibrary(existingAdjustmentFormatIdentifier: "com.example.otherEditor"),
            repository: repository
        )

        let availability = await service.availability(localIdentifier: identifier)

        XCTAssertEqual(availability, .editedElsewhere)
        let stored = try await repository.loadScores(localIdentifiers: [identifier])
        XCTAssertEqual(stored[identifier]?.isAlikeEnhanced, false)
    }

    func testAnEditRevertedOutsideAlikeClearsTheCachedMarker() async throws {
        let repository = MockPhotoQualityScoreRepository()
        await repository.setStoredScores([makeScore(isAlikeEnhanced: true)])
        let service = makeService(library: FakePhotoLibrary(), repository: repository)

        let availability = await service.availability(localIdentifier: identifier)

        XCTAssertEqual(availability, .available)
        let stored = try await repository.loadScores(localIdentifiers: [identifier])
        XCTAssertEqual(stored[identifier]?.isAlikeEnhanced, false)
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
            requestBuilder: { _, purpose in await library.makeRequest(purpose: purpose) },
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
    private let isSupported: Bool
    private let existingAdjustmentFormatIdentifier: String?
    private let originalError: Error?
    private let saveError: Error?

    private(set) var requestedPurposes: [PhotoEnhancementRequestPurpose] = []
    private(set) var savedAdjustmentData: Data?
    private(set) var savedRecipeStepCount: Int?
    private(set) var didRevert = false

    init(
        isMissing: Bool = false,
        isEditable: Bool = true,
        isSupported: Bool = true,
        existingAdjustmentFormatIdentifier: String? = nil,
        originalError: Error? = nil,
        saveError: Error? = nil
    ) {
        self.isMissing = isMissing
        self.isEditable = isEditable
        self.isSupported = isSupported
        self.existingAdjustmentFormatIdentifier = existingAdjustmentFormatIdentifier
        self.originalError = originalError
        self.saveError = saveError
    }

    func makeRequest(purpose: PhotoEnhancementRequestPurpose) -> ResolvedPhotoEnhancementRequest? {
        requestedPurposes.append(purpose)
        guard !isMissing else { return nil }
        return ResolvedPhotoEnhancementRequest(
            isEditable: isEditable,
            isSupported: isSupported,
            existingAdjustmentFormatIdentifier: existingAdjustmentFormatIdentifier,
            loadOriginal: { [self] in
                if let originalError = await self.originalError { throw originalError }
                return (
                    CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 256, height: 256)),
                    // A rotated source: the saved rendering must keep the
                    // library's pixel geometry, not the display one.
                    6
                )
            },
            saveEnhanced: { [self] _, recipe, adjustmentData in
                if let saveError = await self.saveError { throw saveError }
                await self.recordSave(adjustmentData, recipeStepCount: recipe.steps.count)
            },
            revertToOriginal: { [self] in
                await self.recordRevert()
            }
        )
    }

    private func recordSave(_ adjustmentData: Data, recipeStepCount: Int) {
        savedAdjustmentData = adjustmentData
        savedRecipeStepCount = recipeStepCount
    }

    private func recordRevert() {
        didRevert = true
    }
}
