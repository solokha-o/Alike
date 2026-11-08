import Core
import CoreGraphics
import Photos
import Foundation
import Testing
@testable import Details

@MainActor
struct ClusterDetailsEnhancementTests {
    private let clusterID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!

    // MARK: - Availability

    @Test func testActionIsHiddenWithoutAnEnhancementService() async {
        let viewModel = makeViewModel(service: nil)

        await viewModel.load()

        #expect(viewModel.enhancementState == .unavailable)
        #expect(!viewModel.isEnhancementActionVisible)
    }

    @Test func testActionIsHiddenWhenTheAssetCannotBeEdited() async {
        let service = FakeEnhancementService(canEnhance: false)
        let viewModel = makeViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.enhancementState == .unavailable)
        #expect(!viewModel.isEnhancementActionVisible)
    }

    @Test func testAnAlreadyEnhancedBestShotLoadsAsApplied() async {
        let service = FakeEnhancementService(isEnhanced: true)
        let viewModel = makeViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.enhancementState == .applied)
        #expect(viewModel.isBestShotEnhanced)
    }

    @Test func testAvailabilityIsAskedOnceWhenOpeningTheCluster() async {
        let service = FakeEnhancementService()
        let viewModel = makeViewModel(service: service)

        await viewModel.load()

        // Each question to the library resolves the photo, which can download a
        // full-size original; opening a cluster asks once.
        let callCount = await service.availabilityCallCount
        #expect(callCount == 1)
    }

    // MARK: - Happy path

    @Test func testPreviewThenApplyThenRevertWalksTheWholeStateMachine() async {
        let service = FakeEnhancementService()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        #expect(viewModel.enhancementState == .idle)

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        #expect(viewModel.enhancementState == .previewing)
        #expect(viewModel.enhancementPreview != nil)

        await viewModel.applyEnhancement(for: "best")

        #expect(viewModel.enhancementState == .applied)
        #expect(viewModel.isBestShotEnhanced)
        #expect(viewModel.enhancementPreview == nil)

        await viewModel.revertEnhancement()

        #expect(viewModel.enhancementState == .idle)
        #expect(!viewModel.isBestShotEnhanced)
        let didRevert = await service.didRevert
        #expect(didRevert)
    }

    @Test func testCancellingThePreviewWritesNothing() async {
        let service = FakeEnhancementService()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        viewModel.dismissEnhancementPreview()

        #expect(viewModel.enhancementState == .idle)
        #expect(viewModel.enhancementPreview == nil)
        let didApply = await service.didApply
        #expect(!didApply)
        #expect(!viewModel.isBestShotEnhanced)
    }

    /// Cancel is offered while the original is still coming down from iCloud.
    /// Leaving `.preparingPreview` behind there kept the action disabled for
    /// the rest of the screen's life.
    @Test func testCancellingWhileThePreviewIsStillPreparingReturnsToIdle() async {
        let service = FakeEnhancementService(previewDelay: true)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let previewing = Task {
            await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")
        }
        await Task.yield()
        #expect(viewModel.enhancementState == .preparingPreview)

        viewModel.dismissEnhancementPreview()

        #expect(viewModel.enhancementState == .idle)
        #expect(viewModel.enhancementPreview == nil)

        // The render the user walked away from lands afterwards and must not
        // re-open the preview it belonged to.
        await service.releasePreview()
        await previewing.value

        #expect(viewModel.enhancementState == .idle)
        #expect(viewModel.enhancementPreview == nil)
    }

    /// Thumbnails are cached under the asset's modification date, so a photo
    /// Alike just wrote to has to be re-read or the tile keeps showing the
    /// picture from before the edit.
    @Test func testApplyingRereadsTheEditedPhoto() async {
        let service = FakeEnhancementService()
        let refreshed = RefreshedAssetRecorder()
        let viewModel = makeViewModel(service: service, refreshedAssetIdentifiers: refreshed)
        await viewModel.load()

        await viewModel.applyEnhancement(for: "best")

        #expect(refreshed.identifiers == ["best"])
    }

    @Test func testRevertingRereadsTheRestoredPhoto() async {
        let service = FakeEnhancementService(isEnhanced: true)
        let refreshed = RefreshedAssetRecorder()
        let viewModel = makeViewModel(service: service, refreshedAssetIdentifiers: refreshed)
        await viewModel.load()

        await viewModel.revertEnhancement()

        #expect(refreshed.identifiers == ["best"])
    }

    @Test func testAPhotoEditedElsewhereKeepsTheActionAndCarriesTheNote() async {
        let service = FakeEnhancementService(isEditedElsewhere: true)
        let viewModel = makeViewModel(service: service)

        await viewModel.load()

        #expect(viewModel.enhancementState == .idle)
        #expect(viewModel.isEnhancementActionVisible)
        #expect(viewModel.isBestShotEditedElsewhere)
        #expect(!viewModel.isBestShotEnhanced)
    }

    @Test func testApplyingToAPhotoEditedElsewhereCarriesTheUsersAgreement() async {
        let service = FakeEnhancementService(isEditedElsewhere: true)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.applyEnhancement(for: "best")

        let didReplace = await service.didReplaceOtherEdits
        #expect(didReplace)
        #expect(viewModel.enhancementState == .applied)
        #expect(!viewModel.isBestShotEditedElsewhere)
    }

    @Test func testApplyingToAnUntouchedPhotoDoesNotClaimToReplaceAnything() async {
        let service = FakeEnhancementService()
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.applyEnhancement(for: "best")

        let didReplace = await service.didReplaceOtherEdits
        #expect(!didReplace)
    }

    /// Apply dismisses the preview at once and the grid stays interactive, so
    /// the edit can finish after the user has moved the Best Shot elsewhere.
    @Test func testApplyingFinishesOnThePhotoItStartedOn() async {
        let service = FakeEnhancementService(applyDelay: true)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        let applying = Task { await viewModel.applyEnhancement(for: "best") }
        await Task.yield()
        viewModel.setBestShot("other")
        await service.releaseApply()
        await applying.value

        // The badge belongs to the photo that was edited …
        #expect(viewModel.isEnhanced("best"))
        // … and the shared state describes the photo now on the tile, which
        // nobody has enhanced.
        #expect(!viewModel.isEnhanced("other"))
        #expect(viewModel.enhancementState != PhotoEnhancementState.applied)
    }

    @Test func testRevertingFinishesOnThePhotoItStartedOn() async {
        let service = FakeEnhancementService(isEnhanced: true, revertDelay: true)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        #expect(viewModel.isEnhanced("best"))

        let reverting = Task { await viewModel.revertEnhancement() }
        await Task.yield()
        viewModel.setBestShot("other")
        await service.releaseRevert()
        await reverting.value

        #expect(!viewModel.isEnhanced("best"))
        #expect(viewModel.enhancementState != PhotoEnhancementState.reverting)
    }

    /// The screen is interactive before scoring finishes, so a refinement can
    /// land while the preview cover is open. It must not move the Best Shot
    /// under a preview the user is looking at.
    @Test func testOpeningThePreviewFreezesALateRanking() async throws {
        let analyzer = StallingQualityAnalyzer()
        let viewModel = makeViewModel(service: FakeEnhancementService(), qualityAnalyzer: analyzer)

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }
        #expect(viewModel.bestShotAssetID == "best")

        // The action is tapped: the photo is frozen here, before the cover's
        // task ever runs.
        let requestedID = try #require(viewModel.beginEnhancementRequest())
        #expect(requestedID == "best")
        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: requestedID)
        #expect(viewModel.enhancementState == .previewing)

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

        #expect(viewModel.bestShotAssetID == "best")
        #expect(viewModel.enhancementState == .previewing)
        #expect(viewModel.enhancementPreview != nil)
    }

    /// The tap and the cover's task are two moments; the ranking must be frozen
    /// at the first of them, or the cover opens on a different photo.
    @Test func testTheAssetIsFrozenWhenTheActionIsTappedNotWhenThePreviewStarts() async throws {
        let analyzer = StallingQualityAnalyzer()
        let viewModel = makeViewModel(service: FakeEnhancementService(), qualityAnalyzer: analyzer)

        let loading = Task { await viewModel.load() }
        for _ in 0..<1_000 where !viewModel.hasLoadedReviewState {
            await Task.yield()
        }

        let requestedID = try #require(viewModel.beginEnhancementRequest())

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

        #expect(requestedID == "best")
        #expect(viewModel.bestShotAssetID == "best")
        #expect(viewModel.enhancementState == .previewing)
        #expect(viewModel.enhancementPreview != nil)
    }

    /// A preview for a photo that is no longer the Best Shot renders nothing.
    @Test func testAStalePreviewRequestIsIgnored() async {
        let viewModel = makeViewModel(service: FakeEnhancementService())
        await viewModel.load()

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "other")

        #expect(viewModel.enhancementPreview == nil)
        #expect(viewModel.enhancementState == .idle)
    }

    // MARK: - Failures

    @Test func testPreviewFailureLeavesTheReviewUntouched() async {
        let service = FakeEnhancementService(previewError: .originalUnavailable)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        let bestShotBefore = viewModel.bestShotAssetID
        let statusBefore = viewModel.reviewStatus

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        #expect(viewModel.enhancementState == .failed(.originalUnavailable))
        #expect(viewModel.actionErrorMessage == DetailsL10n.ClusterDetails.enhancementOriginalUnavailable)
        #expect(viewModel.bestShotAssetID == bestShotBefore)
        #expect(viewModel.reviewStatus == statusBefore)
        #expect(!viewModel.isBestShotEnhanced)
    }

    @Test func testApplyFailureKeepsTheStateAndOffersRecovery() async {
        let service = FakeEnhancementService(applyError: .saveFailed)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        await viewModel.applyEnhancement(for: "best")

        #expect(viewModel.enhancementState == .failed(.saveFailed))
        #expect(!viewModel.isBestShotEnhanced)
        #expect(viewModel.actionErrorMessage == DetailsL10n.ClusterDetails.enhancementSaveFailed)
        #expect(viewModel.actionErrorTitle == DetailsL10n.ClusterDetails.enhancementUnavailableTitle)

        viewModel.clearActionError()

        #expect(viewModel.enhancementState == .previewing)
        #expect(viewModel.actionErrorMessage == nil)
    }

    @Test func testRevertFailureKeepsThePhotoMarkedEnhanced() async {
        let service = FakeEnhancementService(isEnhanced: true, revertError: .notEnhancedByAlike)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.revertEnhancement()

        #expect(viewModel.enhancementState == .failed(.notEnhancedByAlike))
        #expect(viewModel.isBestShotEnhanced)
        #expect(viewModel.actionErrorMessage == DetailsL10n.ClusterDetails.enhancementNotOurs)

        viewModel.clearActionError()

        #expect(viewModel.enhancementState == .applied)
    }

    @Test func testRenderAndSaveFailuresHaveTheirOwnCopy() async {
        let renderFailure = makeViewModel(service: FakeEnhancementService(previewError: .renderFailed))
        await renderFailure.load()
        await renderFailure.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        #expect(renderFailure.actionErrorMessage == DetailsL10n.ClusterDetails.enhancementRenderFailed)

        let saveFailure = makeViewModel(service: FakeEnhancementService(applyError: .saveFailed))
        await saveFailure.load()
        await saveFailure.applyEnhancement(for: "best")

        #expect(saveFailure.actionErrorMessage == DetailsL10n.ClusterDetails.enhancementSaveFailed)
        #expect(renderFailure.actionErrorMessage != saveFailure.actionErrorMessage, "The two steps must be distinguishable from the alert alone")
    }

    @Test func testAnUnsupportedAssetExplainsItself() async {
        let viewModel = makeViewModel(service: FakeEnhancementService(previewError: .unsupportedAsset))
        await viewModel.load()

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        #expect(viewModel.actionErrorMessage == DetailsL10n.ClusterDetails.enhancementUnsupportedAsset)
        #expect(viewModel.actionErrorTitle == DetailsL10n.ClusterDetails.enhancementUnavailableTitle)
    }

    @Test func testDismissingAnEnhancementAlertRestoresTheCleanupTitle() async {
        let viewModel = makeViewModel(service: FakeEnhancementService(applyError: .saveFailed))
        await viewModel.load()
        await viewModel.applyEnhancement(for: "best")

        viewModel.clearActionError()

        #expect(viewModel.actionErrorTitle == DetailsL10n.Common.cleanupUnavailable)
    }

    @Test func testNotAuthorizedFailureOffersSettings() async {
        let service = FakeEnhancementService(previewError: .notAuthorized)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100), for: "best")

        #expect(viewModel.shouldOfferOpenSettings)
        #expect(viewModel.actionErrorMessage == DetailsL10n.Common.alikeNeedsPhotoLibraryAccess)
    }

    // MARK: - Helpers

    private func makeViewModel(
        service: FakeEnhancementService?,
        qualityAnalyzer: any PhotoQualityAnalyzing = NoOpPhotoQualityAnalyzer(),
        refreshedAssetIdentifiers: RefreshedAssetRecorder? = nil
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
            completionDelay: {},
            // A test has no photo library to re-read from; recording the ask is
            // what says the grid was told to reload that photo.
            assetRefresher: { identifier in
                refreshedAssetIdentifiers?.record(identifier)
                return nil
            }
        )
    }
}

/// Records which assets the view model asked the library to re-read.
@MainActor
final class RefreshedAssetRecorder {
    private(set) var identifiers: [String] = []

    func record(_ identifier: String) {
        identifiers.append(identifier)
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
    private let previewDelay: Bool
    private var applyContinuation: CheckedContinuation<Void, Never>?
    private var revertContinuation: CheckedContinuation<Void, Never>?
    private var previewContinuation: CheckedContinuation<Void, Never>?
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
        revertDelay: Bool = false,
        previewDelay: Bool = false
    ) {
        self.canEnhanceAsset = canEnhance
        self.isEditedElsewhere = isEditedElsewhere
        // Enhancement belongs to a photo, so the double tracks it per photo.
        self.enhancedIdentifiers = isEnhanced ? ["best"] : []
        self.applyDelay = applyDelay
        self.revertDelay = revertDelay
        self.previewDelay = previewDelay
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
        if previewDelay {
            await withCheckedContinuation { continuation in
                previewContinuation = continuation
            }
        }
        if let previewError { throw previewError }
        return Self.makeImage(size: targetSize)
    }

    func releasePreview() {
        previewContinuation?.resume()
        previewContinuation = nil
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
