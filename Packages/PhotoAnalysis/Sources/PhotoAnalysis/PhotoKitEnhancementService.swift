import Core
import CoreGraphics
import CoreImage
import Foundation
@preconcurrency import Photos

/// One resolved photo-library edit, so the service can be tested without a real
/// photo library: everything PhotoKit does sits behind these closures.
struct ResolvedPhotoEnhancementRequest: Sendable {
    /// `false` for assets the user may not edit (shared, iCloud-restricted…).
    let isEditable: Bool
    /// Format identifier of the adjustment already on the asset, if any.
    let existingAdjustmentFormatIdentifier: String?
    /// The unedited original, as the library hands it back.
    let loadOriginal: @Sendable () async throws -> CIImage
    /// Writes the rendered image and the adjustment data as one edit.
    let saveEnhanced: @Sendable (CIImage, Data) async throws -> Void
    let revertToOriginal: @Sendable () async throws -> Void
}

/// Non-destructive auto-enhancement backed by PhotoKit content editing.
///
/// The library keeps the original, no duplicate asset is created, the edit is
/// visible in Photos and every other app, and `revertAssetContentToOriginal()`
/// is the one-step undo the requirements ask for.
public actor PhotoKitEnhancementService: PhotoEnhancementService {
    typealias AuthorizationStatusProvider = @Sendable () -> PHAuthorizationStatus
    typealias RequestBuilder = @Sendable (String) async -> ResolvedPhotoEnhancementRequest?

    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let requestBuilder: RequestBuilder
    private let renderer: AutoEnhancementRenderer
    private let qualityScoreRepository: (any PhotoQualityScoreRepository)?
    private let config: PhotoQualityScoringConfig

    public init(
        qualityScoreRepository: (any PhotoQualityScoreRepository)? = nil,
        config: PhotoQualityScoringConfig = .current
    ) {
        self.init(
            authorizationStatusProvider: PhotoKitEnhancementService.defaultAuthorizationStatusProvider,
            requestBuilder: PhotoKitEnhancementService.defaultRequestBuilder,
            qualityScoreRepository: qualityScoreRepository,
            config: config
        )
    }

    init(
        authorizationStatusProvider: @escaping AuthorizationStatusProvider,
        requestBuilder: @escaping RequestBuilder,
        renderer: AutoEnhancementRenderer = AutoEnhancementRenderer(),
        qualityScoreRepository: (any PhotoQualityScoreRepository)? = nil,
        config: PhotoQualityScoringConfig = .current
    ) {
        self.authorizationStatusProvider = authorizationStatusProvider
        self.requestBuilder = requestBuilder
        self.renderer = renderer
        self.qualityScoreRepository = qualityScoreRepository
        self.config = config
    }

    // MARK: - PhotoEnhancementService

    public func canEnhance(localIdentifier: String) async -> Bool {
        guard (try? authorize()) != nil else { return false }
        guard let request = await requestBuilder(localIdentifier) else { return false }
        return request.isEditable
    }

    public func renderPreview(localIdentifier: String, targetSize: CGSize) async throws -> CGImage {
        let request = try await editableRequest(for: localIdentifier)
        let original = try await loadOriginal(with: request)
        let enhanced = renderer.render(
            original,
            allowsSharpening: await allowsSharpening(localIdentifier: localIdentifier)
        ).image
        guard let preview = renderer.makePreview(of: enhanced, targetSize: targetSize) else {
            throw PhotoEnhancementError.renderFailed
        }
        return preview
    }

    public func applyEnhancement(localIdentifier: String) async throws -> PhotoEnhancementAdjustment {
        let request = try await editableRequest(for: localIdentifier)
        let original = try await loadOriginal(with: request)
        let rendered = renderer.render(
            original,
            allowsSharpening: await allowsSharpening(localIdentifier: localIdentifier)
        )

        let encodedAdjustment: Data
        do {
            encodedAdjustment = try JSONEncoder().encode(rendered.adjustment)
        } catch {
            throw PhotoEnhancementError.renderFailed
        }

        do {
            try await request.saveEnhanced(rendered.image, encodedAdjustment)
        } catch let error as PhotoEnhancementError {
            throw error
        } catch {
            AppLog.photoKit.error(
                "\(AppLog.tag(.error, "Enhancement save failed: \(error.localizedDescription)"))"
            )
            throw PhotoEnhancementError.saveFailed
        }

        // Scoring must keep measuring the original: our own edit may not lift
        // the Best Shot score or hide the defects it was ranked on.
        await setEnhancedFlag(true, localIdentifier: localIdentifier)
        return rendered.adjustment
    }

    public func revertToOriginal(localIdentifier: String) async throws {
        let request = try await editableRequest(for: localIdentifier)
        guard request.existingAdjustmentFormatIdentifier == PhotoEnhancementAdjustment.formatIdentifier else {
            throw PhotoEnhancementError.notEnhancedByAlike
        }

        do {
            try await request.revertToOriginal()
        } catch let error as PhotoEnhancementError {
            throw error
        } catch {
            AppLog.photoKit.error(
                "\(AppLog.tag(.error, "Revert failed: \(error.localizedDescription)"))"
            )
            throw PhotoEnhancementError.saveFailed
        }

        await setEnhancedFlag(false, localIdentifier: localIdentifier)
    }

    public func isEnhancedByAlike(localIdentifier: String) async -> Bool {
        guard let request = await requestBuilder(localIdentifier) else { return false }
        return request.existingAdjustmentFormatIdentifier == PhotoEnhancementAdjustment.formatIdentifier
    }

    // MARK: - Helpers

    private func editableRequest(for localIdentifier: String) async throws -> ResolvedPhotoEnhancementRequest {
        try authorize()
        guard let request = await requestBuilder(localIdentifier) else {
            throw PhotoEnhancementError.originalUnavailable
        }
        guard request.isEditable else {
            throw PhotoEnhancementError.limitedAccessNotEditable
        }
        return request
    }

    private func loadOriginal(with request: ResolvedPhotoEnhancementRequest) async throws -> CIImage {
        do {
            return try await request.loadOriginal()
        } catch let error as PhotoEnhancementError {
            throw error
        } catch {
            throw PhotoEnhancementError.originalUnavailable
        }
    }

    private func authorize() throws {
        switch authorizationStatusProvider() {
        case .authorized:
            return
        case .limited:
            // Limited access can read the photo but never edit it, so the UI
            // must find out before it offers the action.
            throw PhotoEnhancementError.limitedAccessNotEditable
        default:
            throw PhotoEnhancementError.notAuthorized
        }
    }

    /// Sharpening is only ever applied to a frame that is already sharp: an
    /// enhancement must not make a blurred photo look acceptable.
    private func allowsSharpening(localIdentifier: String) async -> Bool {
        guard let qualityScoreRepository else { return false }
        guard let score = try? await qualityScoreRepository
            .loadScores(localIdentifiers: [localIdentifier])[localIdentifier] else {
            return false
        }
        guard score.signals.isUsable else { return false }
        let sharpness = score.signals.subjectSharpness ?? score.signals.globalSharpness
        return sharpness >= config.absoluteSharpnessFloor
    }

    private func setEnhancedFlag(_ isEnhanced: Bool, localIdentifier: String) async {
        guard let qualityScoreRepository else { return }
        do {
            let stored = try await qualityScoreRepository.loadScores(localIdentifiers: [localIdentifier])
            guard let score = stored[localIdentifier], score.isAlikeEnhanced != isEnhanced else { return }
            try await qualityScoreRepository.saveScores([
                PhotoQualityScore(
                    localIdentifier: score.localIdentifier,
                    sourceModificationDate: score.sourceModificationDate,
                    scoringModelVersion: score.scoringModelVersion,
                    thumbnailConfigVersion: score.thumbnailConfigVersion,
                    // The pre-enhancement signals are kept on purpose.
                    signals: score.signals,
                    scoredAt: score.scoredAt,
                    isAlikeEnhanced: isEnhanced
                )
            ])
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to flag enhanced asset in the score cache: \(error.localizedDescription)"))"
            )
        }
    }
}

// MARK: - PhotoKit wiring

private extension PhotoKitEnhancementService {
    static func defaultAuthorizationStatusProvider() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Resolves one asset into the closures the service works with. Requesting
    /// the content editing input is also how the existing adjustment data — and
    /// therefore "who edited this photo" — becomes known.
    static func defaultRequestBuilder(localIdentifier: String) async -> ResolvedPhotoEnhancementRequest? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        let options = PHContentEditingInputRequestOptions()
        // Accepting any adjustment data is what makes the library hand back the
        // untouched original plus whatever edit is currently applied.
        options.canHandleAdjustmentData = { _ in true }
        options.isNetworkAccessAllowed = true

        // PhotoKit's editing input is not Sendable, but it is only ever touched
        // inside these closures, one at a time, on the caller's task.
        guard let editingInput = await requestContentEditingInput(for: asset, options: options) else {
            return nil
        }

        let renderer = AutoEnhancementRenderer()
        return ResolvedPhotoEnhancementRequest(
            isEditable: asset.canPerform(.content),
            existingAdjustmentFormatIdentifier: editingInput.value.adjustmentData?.formatIdentifier,
            loadOriginal: {
                let input = editingInput.value
                guard let url = input.fullSizeImageURL,
                      let image = CIImage(contentsOf: url) else {
                    throw PhotoEnhancementError.originalUnavailable
                }
                return image.oriented(forExifOrientation: input.fullSizeImageOrientation)
            },
            saveEnhanced: { image, adjustmentData in
                let output = PHContentEditingOutput(contentEditingInput: editingInput.value)
                output.adjustmentData = PHAdjustmentData(
                    formatIdentifier: PhotoEnhancementAdjustment.formatIdentifier,
                    formatVersion: PhotoEnhancementAdjustment.formatVersion,
                    data: adjustmentData
                )
                do {
                    try renderer.writeJPEG(image, to: output.renderedContentURL)
                } catch {
                    throw PhotoEnhancementError.renderFailed
                }
                try await performChanges {
                    let request = PHAssetChangeRequest(for: asset)
                    request.contentEditingOutput = output
                }
            },
            revertToOriginal: {
                try await performChanges {
                    PHAssetChangeRequest(for: asset).revertAssetContentToOriginal()
                }
            }
        )
    }

    static func requestContentEditingInput(
        for asset: PHAsset,
        options: PHContentEditingInputRequestOptions
    ) async -> UncheckedSendableBox<PHContentEditingInput>? {
        await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, _ in
                continuation.resume(returning: input.map(UncheckedSendableBox.init))
            }
        }
    }

    static func performChanges(_ changes: @escaping @Sendable () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoEnhancementError.saveFailed)
                }
            }
        }
    }
}

/// Carries a non-`Sendable` PhotoKit object across the closures of one resolved
/// request, which are never run concurrently with each other.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
