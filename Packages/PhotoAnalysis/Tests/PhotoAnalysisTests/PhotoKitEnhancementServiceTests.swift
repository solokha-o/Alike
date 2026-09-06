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

    /// With consent given, the enhancement is written on top of the other app's
    /// result — nothing of theirs is destroyed, and a single revert still takes
    /// the photo back to the camera original.
    func testEnhancingOnTopOfAForeignEditWritesWithoutRevertingIt() async throws {
        let library = FakePhotoLibrary(existingAdjustmentFormatIdentifier: "com.example.otherEditor")
        let service = makeService(library: library)

        _ = try await service.applyEnhancement(
            localIdentifier: identifier,
            replacingOtherEdits: true
        )

        let didRevert = await library.didRevert
        let saved = await library.savedAdjustmentData
        XCTAssertFalse(didRevert, "The other app's edit is built on, not undone")
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

    // MARK: - An unreadable editing input

    /// A photo that is not local cannot be read for its adjustment: judging
    /// availability may not pull a full-size original down from iCloud. Calling
    /// that "no edit" cleared Alike's marker, and the score cache then sent the
    /// photo back to be measured against its own enhanced pixels.
    func testAnUnreadableInputKeepsTheEnhancedMarkerAndAnswersFromIt() async throws {
        let repository = MockPhotoQualityScoreRepository()
        try await repository.saveScores([makeScore(isAlikeEnhanced: true)])
        let service = makeService(
            library: FakePhotoLibrary(isAdjustmentDataReadable: false),
            repository: repository
        )

        let availability = await service.availability(localIdentifier: identifier)

        XCTAssertEqual(availability, .enhanced)
        let stored = try await repository.loadScores(localIdentifiers: [identifier])
        XCTAssertEqual(stored[identifier]?.isAlikeEnhanced, true)
    }

    /// The same unreadable photo with nothing recorded about it keeps offering
    /// the action, exactly as before: the action must not depend on a photo
    /// being resolvable without the network.
    func testAnUnreadableInputWithNoMarkerStillOffersTheAction() async throws {
        let repository = MockPhotoQualityScoreRepository()
        try await repository.saveScores([makeScore(isAlikeEnhanced: false)])
        let service = makeService(
            library: FakePhotoLibrary(isAdjustmentDataReadable: false),
            repository: repository
        )

        let availability = await service.availability(localIdentifier: identifier)

        XCTAssertEqual(availability, .available)
        let stored = try await repository.loadScores(localIdentifiers: [identifier])
        XCTAssertEqual(stored[identifier]?.isAlikeEnhanced, false)
    }

    /// A readable photo that genuinely carries no edit still clears the marker.
    /// That is the path the unknown state was wrongly sharing.
    func testAReadableInputWithNoEditStillClearsTheMarker() async throws {
        let repository = MockPhotoQualityScoreRepository()
        try await repository.saveScores([makeScore(isAlikeEnhanced: true)])
        let service = makeService(library: FakePhotoLibrary(), repository: repository)

        let availability = await service.availability(localIdentifier: identifier)

        XCTAssertEqual(availability, .available)
        let stored = try await repository.loadScores(localIdentifiers: [identifier])
        XCTAssertEqual(stored[identifier]?.isAlikeEnhanced, false)
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

    /// The consent question is what stands between another app's edit and ours.
    /// Asked on the cheap pass alone it cannot be answered for a photo that is
    /// not local, and the edit — which does reach the network — would then lay
    /// Alike's work over someone else's without ever saying so.
    func testApplyingRefusesAnotherAppsEditThatOnlyTheNetworkCanSee() async {
        let library = FakePhotoLibrary(
            existingAdjustmentFormatIdentifier: "com.example.otherEditor",
            isLocallyReadable: false
        )
        let service = makeService(library: library)

        await assertThrows(.editedInAnotherApp) {
            _ = try await service.applyEnhancement(localIdentifier: self.identifier)
        }

        let saved = await library.savedAdjustmentData
        XCTAssertNil(saved)
        // Offering the action stays local: only the edit itself may reach out.
        let purposes = await library.requestedPurposes
        XCTAssertEqual(purposes, [.availabilityAllowingNetwork])
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
    private let isAdjustmentDataReadable: Bool
    /// `false` for a photo that is not on the device: the cheap availability
    /// pass reads nothing, while the passes that may use the network do.
    private let isLocallyReadable: Bool
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
        isAdjustmentDataReadable: Bool = true,
        isLocallyReadable: Bool = true,
        originalError: Error? = nil,
        saveError: Error? = nil
    ) {
        self.isMissing = isMissing
        self.isEditable = isEditable
        self.isSupported = isSupported
        self.existingAdjustmentFormatIdentifier = existingAdjustmentFormatIdentifier
        self.isAdjustmentDataReadable = isAdjustmentDataReadable
        self.isLocallyReadable = isLocallyReadable
        self.originalError = originalError
        self.saveError = saveError
    }

    func makeRequest(purpose: PhotoEnhancementRequestPurpose) -> ResolvedPhotoEnhancementRequest? {
        requestedPurposes.append(purpose)
        guard !isMissing else { return nil }
        let isReadable = isAdjustmentDataReadable
            && (isLocallyReadable || purpose != .availability)
        return ResolvedPhotoEnhancementRequest(
            isEditable: isEditable,
            isSupported: isSupported,
            existingAdjustmentFormatIdentifier: isReadable ? existingAdjustmentFormatIdentifier : nil,
            isAdjustmentDataReadable: isReadable,
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
