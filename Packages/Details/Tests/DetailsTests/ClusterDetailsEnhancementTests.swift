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

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100))

        XCTAssertEqual(viewModel.enhancementState, .previewing)
        XCTAssertNotNil(viewModel.enhancementPreview)

        await viewModel.applyEnhancement()

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
        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100))

        viewModel.dismissEnhancementPreview()

        XCTAssertEqual(viewModel.enhancementState, .idle)
        XCTAssertNil(viewModel.enhancementPreview)
        let didApply = await service.didApply
        XCTAssertFalse(didApply)
        XCTAssertFalse(viewModel.isBestShotEnhanced)
    }

    // MARK: - Failures

    func testPreviewFailureLeavesTheReviewUntouched() async {
        let service = FakeEnhancementService(previewError: .originalUnavailable)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()
        let bestShotBefore = viewModel.bestShotAssetID
        let statusBefore = viewModel.reviewStatus

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100))

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
        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100))

        await viewModel.applyEnhancement()

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
        await renderFailure.enhance(previewSize: CGSize(width: 100, height: 100))

        XCTAssertEqual(renderFailure.actionErrorMessage, DetailsL10n.ClusterDetails.enhancementRenderFailed)

        let saveFailure = makeViewModel(service: FakeEnhancementService(applyError: .saveFailed))
        await saveFailure.load()
        await saveFailure.applyEnhancement()

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

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100))

        XCTAssertEqual(viewModel.actionErrorMessage, DetailsL10n.ClusterDetails.enhancementUnsupportedAsset)
        XCTAssertEqual(viewModel.actionErrorTitle, DetailsL10n.ClusterDetails.enhancementUnavailableTitle)
    }

    func testDismissingAnEnhancementAlertRestoresTheCleanupTitle() async {
        let viewModel = makeViewModel(service: FakeEnhancementService(applyError: .saveFailed))
        await viewModel.load()
        await viewModel.applyEnhancement()

        viewModel.clearActionError()

        XCTAssertEqual(viewModel.actionErrorTitle, DetailsL10n.Common.cleanupUnavailable)
    }

    func testNotAuthorizedFailureOffersSettings() async {
        let service = FakeEnhancementService(previewError: .notAuthorized)
        let viewModel = makeViewModel(service: service)
        await viewModel.load()

        await viewModel.enhance(previewSize: CGSize(width: 100, height: 100))

        XCTAssertTrue(viewModel.shouldOfferOpenSettings)
        XCTAssertEqual(viewModel.actionErrorMessage, DetailsL10n.Common.alikeNeedsPhotoLibraryAccess)
    }

    // MARK: - Helpers

    private func makeViewModel(service: FakeEnhancementService?) -> ClusterDetailsViewModel {
        ClusterDetailsViewModel(
            cluster: PhotoCluster(id: clusterID, assets: []),
            reviewRepository: MockClusterReviewStateRepository(),
            cleanupService: MockPhotoCleanupService(),
            cleanupHistoryRepository: MockCleanupHistoryRepository(),
            premiumAccess: PremiumAccessController(),
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

/// Enhancement service that never touches a photo library: it records what was
/// asked of it and fails exactly where a test wants it to.
private actor FakeEnhancementService: PhotoEnhancementService {
    private let canEnhanceAsset: Bool
    private var isEnhanced: Bool
    private let previewError: PhotoEnhancementError?
    private let applyError: PhotoEnhancementError?
    private let revertError: PhotoEnhancementError?

    private(set) var didApply = false
    private(set) var didRevert = false
    private(set) var availabilityCallCount = 0

    init(
        canEnhance: Bool = true,
        isEnhanced: Bool = false,
        previewError: PhotoEnhancementError? = nil,
        applyError: PhotoEnhancementError? = nil,
        revertError: PhotoEnhancementError? = nil
    ) {
        self.canEnhanceAsset = canEnhance
        self.isEnhanced = isEnhanced
        self.previewError = previewError
        self.applyError = applyError
        self.revertError = revertError
    }

    func availability(localIdentifier _: String) async -> PhotoEnhancementAvailability {
        availabilityCallCount += 1
        guard canEnhanceAsset else { return .unavailable }
        return isEnhanced ? .enhanced : .available
    }

    func renderPreview(localIdentifier _: String, targetSize: CGSize) async throws -> CGImage {
        if let previewError { throw previewError }
        return Self.makeImage(size: targetSize)
    }

    func applyEnhancement(localIdentifier _: String) async throws -> PhotoEnhancementAdjustment {
        if let applyError { throw applyError }
        didApply = true
        isEnhanced = true
        return PhotoEnhancementAdjustment(steps: [])
    }

    func revertToOriginal(localIdentifier _: String) async throws {
        if let revertError { throw revertError }
        didRevert = true
        isEnhanced = false
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
