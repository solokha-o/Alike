import Core
import CoreGraphics
import Photos
import XCTest
@testable import Details

@MainActor
final class ClusterDetailsEnhancementTests: XCTestCase {
    private let clusterID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!

    // MARK: - Availability

    func testActionIsHiddenWithoutAnEnhancementService() async {
        let viewModel = makeViewModel(service: nil)

        await viewModel.load()

        XCTAssertEqual(viewModel.enhancementState, .unavailable)
        XCTAssertFalse(viewModel.isEnhancementActionVisible)
    }

    func testActionIsHiddenWhenTheAssetCannotBeEdited() async {
        let service = FakeEnhancementService(canEnhance: false)
        let viewModel = makeViewModel(service: service)

        await viewModel.load()

        XCTAssertEqual(viewModel.enhancementState, .unavailable)
        XCTAssertFalse(viewModel.isEnhancementActionVisible)
    }

    func testAnAlreadyEnhancedBestShotLoadsAsApplied() async {
        let service = FakeEnhancementService(isEnhanced: true)
        let viewModel = makeViewModel(service: service)

        await viewModel.load()

        XCTAssertEqual(viewModel.enhancementState, .applied)
        XCTAssertTrue(viewModel.isBestShotEnhanced)
    }

    func testAvailabilityIsAskedOnceWhenOpeningTheCluster() async {
        let service = FakeEnhancementService()
        let viewModel = makeViewModel(service: service)

        await viewModel.load()

        // Each question to the library resolves the photo, which can download a
        // full-size original; opening a cluster asks once.
        let callCount = await service.availabilityCallCount
        XCTAssertEqual(callCount, 1)
    }

    // MARK: - Happy path

    func testPreviewThenApplyThenRevertWalksTheWholeStateMachine() async {
        let service = FakeEnhancementService()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        XCTAssertEqual(viewModel.enhancementState, .idle)

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        XCTAssertEqual(viewModel.enhancementState, .previewing)
        XCTAssertNotNil(viewModel.enhancementPreview)

        await viewModel.applyEnhancement(for: "best")

        XCTAssertEqual(viewModel.enhancementState, .applied)
        XCTAssertTrue(viewModel.isBestShotEnhanced)
        XCTAssertNil(viewModel.enhancementPreview)

        await viewModel.revertEnhancement()

        XCTAssertEqual(viewModel.enhancementState, .idle)
        XCTAssertFalse(viewModel.isBestShotEnhanced)
        let didRevert = await service.didRevert
        XCTAssertTrue(didRevert)
    }

    func testCancellingThePreviewWritesNothing() async {
        let service = FakeEnhancementService()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        viewModel.dismissEnhancementPreview()

        XCTAssertEqual(viewModel.enhancementState, .idle)
        XCTAssertNil(viewModel.enhancementPreview)
        let didApply = await service.didApply
        XCTAssertFalse(didApply)
        XCTAssertFalse(viewModel.isBestShotEnhanced)
    }

    func testAPhotoEditedElsewhereKeepsTheActionAndCarriesTheNote() async {
        let service = FakeEnhancementService(isEditedElsewhere: true)
        let viewModel = makeViewModel(service: service)

        await viewModel.load()

        XCTAssertEqual(viewModel.enhancementState, .idle)
        XCTAssertTrue(viewModel.isEnhancementActionVisible)
        XCTAssertTrue(viewModel.isBestShotEditedElsewhere)
        XCTAssertFalse(viewModel.isBestShotEnhanced)
    }

    func testApplyingToAPhotoEditedElsewhereCarriesTheUsersAgreement() async {
        let service = FakeEnhancementService(isEditedElsewhere: true)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.applyEnhancement(for: "best")

        let didReplace = await service.didReplaceOtherEdits
        XCTAssertTrue(didReplace)
        XCTAssertEqual(viewModel.enhancementState, .applied)
        XCTAssertFalse(viewModel.isBestShotEditedElsewhere)
    }

    func testApplyingToAnUntouchedPhotoDoesNotClaimToReplaceAnything() async {
        let service = FakeEnhancementService()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.applyEnhancement(for: "best")

        let didReplace = await service.didReplaceOtherEdits
        XCTAssertFalse(didReplace)
    }

    /// Apply dismisses the preview at once and the grid stays interactive, so
    /// the edit can finish after the user has moved the Best Shot elsewhere.
    func testApplyingFinishesOnThePhotoItStartedOn() async {
        let service = FakeEnhancementService(applyDelay: true)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let applying = Task { await viewModel.applyEnhancement(for: "best") }
        await Task.yield()
        viewModel.setBestShot("other")
        await service.releaseApply()
        await applying.value

        // The badge belongs to the photo that was edited …
        XCTAssertTrue(viewModel.isEnhanced("best"))
        // … and the shared state describes the photo now on the tile, which
        // nobody has enhanced.
        XCTAssertFalse(viewModel.isEnhanced("other"))
        XCTAssertNotEqual(viewModel.enhancementState, PhotoEnhancementState.applied)
    }

    func testRevertingFinishesOnThePhotoItStartedOn() async {
        let service = FakeEnhancementService(isEnhanced: true, revertDelay: true)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        XCTAssertTrue(viewModel.isEnhanced("best"))

        let reverting = Task { await viewModel.revertEnhancement() }
        await Task.yield()
        viewModel.setBestShot("other")
        await service.releaseRevert()
        await reverting.value

        XCTAssertFalse(viewModel.isEnhanced("best"))
        XCTAssertNotEqual(viewModel.enhancementState, PhotoEnhancementState.reverting)
    }

    /// The screen is interactive before scoring finishes, so a refinement can
    /// land while the preview cover is open. It must not move the Best Shot
    /// under a preview the user is looking at.
    func testOpeningThePreviewFreezesALateRanking() async throws {
        let analyzer = StallingQualityAnalyzer()
        let viewModel = makeViewModel(service: FakeEnhancementService(), qualityAnalyzer: analyzer)

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.bestShotAssetID, "best")

        // The action is tapped: the photo is frozen here, before the cover's
        // task ever runs.
        let requestedID = try XCTUnwrap(viewModel.beginEnhancementRequest())
        XCTAssertEqual(requestedID, "best")
        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: requestedID)
        XCTAssertEqual(viewModel.enhancementState, .previewing)

        // Scoring finishes now and would have crowned the other photo.
        let config = PhotoQualityScoringConfig.current
        await analyzer.finish(with: [
            PhotoQualityScore(
                localIdentifier: "best",
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(globalSharpness: 5, subjectLumaStdDev: 0.25, pixelArea: 1_000)
            ),
            PhotoQualityScore(
                localIdentifier: "other",
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(globalSharpness: 90, subjectLumaStdDev: 0.25, pixelArea: 1_000)
            )
        ])
        await loading.value

        XCTAssertEqual(viewModel.bestShotAssetID, "best")
        XCTAssertEqual(viewModel.enhancementState, .previewing)
        XCTAssertNotNil(viewModel.enhancementPreview)
    }

    /// The tap and the cover's task are two moments; the ranking must be frozen
    /// at the first of them, or the cover opens on a different photo.
    func testTheAssetIsFrozenWhenTheActionIsTappedNotWhenThePreviewStarts() async throws {
        let analyzer = StallingQualityAnalyzer()
        let viewModel = makeViewModel(service: FakeEnhancementService(), qualityAnalyzer: analyzer)

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }

        let requestedID = try XCTUnwrap(viewModel.beginEnhancementRequest())

        // Scoring lands in the gap between the tap and the preview task.
        let config = PhotoQualityScoringConfig.current
        await analyzer.finish(with: [
            PhotoQualityScore(
                localIdentifier: "best",
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(globalSharpness: 5, subjectLumaStdDev: 0.25, pixelArea: 1_000)
            ),
            PhotoQualityScore(
                localIdentifier: "other",
                sourceModificationDate: nil,
                scoringModelVersion: config.scoringModelVersion,
                thumbnailConfigVersion: config.thumbnailConfigVersion,
                signals: PhotoQualitySignals(globalSharpness: 90, subjectLumaStdDev: 0.25, pixelArea: 1_000)
            )
        ])
        await loading.value
        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: requestedID)

        XCTAssertEqual(requestedID, "best")
        XCTAssertEqual(viewModel.bestShotAssetID, "best")
        XCTAssertEqual(viewModel.enhancementState, .previewing)
        XCTAssertNotNil(viewModel.enhancementPreview)
    }

    /// A preview for a photo that is no longer the Best Shot renders nothing.
    func testAStalePreviewRequestIsIgnored() async {
        let viewModel = makeViewModel(service: FakeEnhancementService())
        await viewModel.load()

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "other")

        XCTAssertNil(viewModel.enhancementPreview)
        XCTAssertEqual(viewModel.enhancementState, .idle)
    }

    // MARK: - Failures

    func testPreviewFailureLeavesTheReviewUntouched() async {
        let service = FakeEnhancementService(previewError: .originalUnavailable)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        let bestShotBefore = viewModel.bestShotAssetID
        let statusBefore = viewModel.reviewStatus

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        XCTAssertEqual(viewModel.enhancementState, .failed(.originalUnavailable))
        XCTAssertEqual(viewModel.actionErrorMessage, DetailsL10n.ClusterDetails.enhancementOriginalUnavailable)
        XCTAssertEqual(viewModel.bestShotAssetID, bestShotBefore)
        XCTAssertEqual(viewModel.reviewStatus, statusBefore)
        XCTAssertFalse(viewModel.isBestShotEnhanced)
    }

    func testApplyFailureKeepsTheStateAndOffersRecovery() async {
        let service = FakeEnhancementService(applyError: .saveFailed)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        await viewModel.applyEnhancement(for: "best")

        XCTAssertEqual(viewModel.enhancementState, .failed(.saveFailed))
        XCTAssertFalse(viewModel.isBestShotEnhanced)
        XCTAssertEqual(viewModel.actionErrorMessage, DetailsL10n.ClusterDetails.enhancementSaveFailed)
        XCTAssertEqual(viewModel.actionErrorTitle, DetailsL10n.ClusterDetails.enhancementUnavailableTitle)

        viewModel.clearActionError()

        XCTAssertEqual(viewModel.enhancementState, .previewing)
        XCTAssertNil(viewModel.actionErrorMessage)
    }

    func testRevertFailureKeepsThePhotoMarkedEnhanced() async {
        let service = FakeEnhancementService(isEnhanced: true, revertError: .notEnhancedByAlike)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.revertEnhancement()

        XCTAssertEqual(viewModel.enhancementState, .failed(.notEnhancedByAlike))
        XCTAssertTrue(viewModel.isBestShotEnhanced)
        XCTAssertEqual(viewModel.actionErrorMessage, DetailsL10n.ClusterDetails.enhancementNotOurs)

        viewModel.clearActionError()

        XCTAssertEqual(viewModel.enhancementState, .applied)
    }

    func testRenderAndSaveFailuresHaveTheirOwnCopy() async {
        let renderFailure = makeViewModel(service: FakeEnhancementService(previewError: .renderFailed))
        await renderFailure.load()
        await renderFailure.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        XCTAssertEqual(renderFailure.actionErrorMessage, DetailsL10n.ClusterDetails.enhancementRenderFailed)

        let saveFailure = makeViewModel(service: FakeEnhancementService(applyError: .saveFailed))
        await saveFailure.load()
        await saveFailure.applyEnhancement(for: "best")

        XCTAssertEqual(saveFailure.actionErrorMessage, DetailsL10n.ClusterDetails.enhancementSaveFailed)
        XCTAssertNotEqual(
            renderFailure.actionErrorMessage,
            saveFailure.actionErrorMessage,
            "The two steps must be distinguishable from the alert alone"
        )
    }

    func testAnUnsupportedAssetExplainsItself() async {
        let viewModel = makeViewModel(service: FakeEnhancementService(previewError: .unsupportedAsset))
        await viewModel.load()

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        XCTAssertEqual(viewModel.actionErrorMessage, DetailsL10n.ClusterDetails.enhancementUnsupportedAsset)
        XCTAssertEqual(viewModel.actionErrorTitle, DetailsL10n.ClusterDetails.enhancementUnavailableTitle)
    }

    func testDismissingAnEnhancementAlertRestoresTheCleanupTitle() async {
        let viewModel = makeViewModel(service: FakeEnhancementService(applyError: .saveFailed))
        await viewModel.load()
        await viewModel.applyEnhancement(for: "best")

        viewModel.clearActionError()

        XCTAssertEqual(viewModel.actionErrorTitle, DetailsL10n.Common.cleanupUnavailable)
    }

    func testNotAuthorizedFailureOffersSettings() async {
        let service = FakeEnhancementService(previewError: .notAuthorized)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        XCTAssertTrue(viewModel.shouldOfferOpenSettings)
        XCTAssertEqual(viewModel.actionErrorMessage, DetailsL10n.Common.alikeNeedsPhotoLibraryAccess)
    }

    // MARK: - Helpers

    private func makeViewModel(
        service: FakeEnhancementService?,
        qualityAnalyzer: any PhotoQualityAnalyzing = NoOpPhotoQualityAnalyzer()
    ) -> ClusterDetailsViewModel {
        ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: MockClusterReviewStateRepository(),
            cleanupService: MockPhotoCleanupService(),
            cleanupHistoryRepository: MockCleanupHistoryRepository(),
            premiumAccess: PremiumAccessController(),
            qualityAnalyzer: qualityAnalyzer,
            enhancementService: service,
            assetSnapshots: [
                ReviewAssetSnapshot(
                    localIdentifier: "best",
                    isFavorite: true,
                    pixelWidth: 100,
                    pixelHeight: 100,
                    creationDate: Date(timeIntervalSince1970: 20)
                ),
                ReviewAssetSnapshot(
                    localIdentifier: "other",
                    isFavorite: false,
                    pixelWidth: 100,
                    pixelHeight: 100,
                    creationDate: Date(timeIntervalSince1970: 10)
                )
            ],
            completionDelay: {}
        )
    }
}

/// Holds scoring open until the test decides to answer it.
private actor StallingQualityAnalyzer: PhotoQualityAnalyzing {
    private var continuation: CheckedContinuation<[PhotoQualityScore], Never>?
    private var pending: [PhotoQualityScore]?

    func scores(for _: [PHAsset]) async throws -> [PhotoQualityScore] {
        if let pending {
            self.pending = nil
            return pending
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(with scores: [PhotoQualityScore]) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: scores)
        } else {
            pending = scores
        }
    }
}

/// Enhancement service that never touches a photo library: it records what was
/// asked of it and fails exactly where a test wants it to.
private actor FakeEnhancementService: PhotoEnhancementService {
    private let canEnhanceAsset: Bool
    private let isEditedElsewhere: Bool
    private var enhancedIdentifiers: Set<String>
    private let applyDelay: Bool
    private let revertDelay: Bool
    private var applyContinuation: CheckedContinuation<Void, Never>?
    private var revertContinuation: CheckedContinuation<Void, Never>?
    private let previewError: PhotoEnhancementError?
    private let applyError: PhotoEnhancementError?
    private let revertError: PhotoEnhancementError?

    private(set) var didReplaceOtherEdits = false
    private(set) var didApply = false
    private(set) var didRevert = false
    private(set) var availabilityCallCount = 0

    init(
        canEnhance: Bool = true,
        isEditedElsewhere: Bool = false,
        isEnhanced: Bool = false,
        previewError: PhotoEnhancementError? = nil,
        applyError: PhotoEnhancementError? = nil,
        revertError: PhotoEnhancementError? = nil,
        applyDelay: Bool = false,
        revertDelay: Bool = false
    ) {
        self.canEnhanceAsset = canEnhance
        self.isEditedElsewhere = isEditedElsewhere
        // Enhancement belongs to a photo, so the double tracks it per photo.
        self.enhancedIdentifiers = isEnhanced ? ["best"] : []
        self.applyDelay = applyDelay
        self.revertDelay = revertDelay
        self.previewError = previewError
        self.applyError = applyError
        self.revertError = revertError
    }

    func availability(localIdentifier: String) async -> PhotoEnhancementAvailability {
        availabilityCallCount += 1
        guard canEnhanceAsset else { return .unavailable }
        if enhancedIdentifiers.contains(localIdentifier) { return .enhanced }
        return isEditedElsewhere ? .editedElsewhere : .available
    }

    func renderPreview(localIdentifier _: String, targetSize: CGSize) async throws -> CGImage {
        if let previewError { throw previewError }
        return Self.makeImage(size: targetSize)
    }

    func releaseApply() {
        applyContinuation?.resume()
        applyContinuation = nil
    }

    func releaseRevert() {
        revertContinuation?.resume()
        revertContinuation = nil
    }

    func applyEnhancement(
        localIdentifier: String,
        replacingOtherEdits: Bool
    ) async throws -> PhotoEnhancementAdjustment {
        if applyDelay {
            await withCheckedContinuation { continuation in
                applyContinuation = continuation
            }
        }
        if let applyError { throw applyError }
        didApply = true
        didReplaceOtherEdits = replacingOtherEdits
        enhancedIdentifiers.insert(localIdentifier)
        return PhotoEnhancementAdjustment(steps: [])
    }

    func revertToOriginal(localIdentifier: String) async throws {
        if revertDelay {
            await withCheckedContinuation { continuation in
                revertContinuation = continuation
            }
        }
        if let revertError { throw revertError }
        didRevert = true
        enhancedIdentifiers.remove(localIdentifier)
    }

    private static func makeImage(size: CGSize) -> CGImage {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
