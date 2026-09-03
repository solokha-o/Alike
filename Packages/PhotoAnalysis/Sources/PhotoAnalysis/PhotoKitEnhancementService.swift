import Core
import CoreGraphics
import CoreImage
import Foundation
@preconcurrency import Photos

/// Why the asset is being resolved. Checking whether the action can be offered
/// must stay cheap and local; only a real edit may reach for the network.
enum PhotoEnhancementRequestPurpose: Sendable {
    case availability
    case editing
}

/// One resolved photo-library edit, so the service can be tested without a real
/// photo library: everything PhotoKit does sits behind these closures.
struct ResolvedPhotoEnhancementRequest: Sendable {
    /// `false` for assets the user may not edit (shared, iCloud-restricted…).
    let isEditable: Bool
    /// `false` for anything Alike cannot render at all — a video, or a live
    /// asset the library refuses to hand over as an editable Live Photo.
    let isSupported: Bool
    /// Format identifier of the adjustment already on the asset, if any.
    let existingAdjustmentFormatIdentifier: String?
    /// The asset's own modification date and pixel count, so a score can be
    /// cached for a photo that was never analyzed before it is enhanced.
    let sourceModificationDate: Date?
    let pixelArea: Int64
    /// The unedited original still, in the library's own pixel geometry, with
    /// the EXIF orientation Photos applies on top of it.
    let loadOriginal: @Sendable () async throws -> (image: CIImage, exifOrientation: Int32)
    /// Writes the edit as one change: the rendered still, the recipe to replay
    /// on a Live Photo's video frames, and the adjustment data to stamp it with.
    let saveEnhanced: @Sendable (
        CIImage,
        AutoEnhancementRenderer.AppliedRecipe,
        Data
    ) async throws -> Void
    let revertToOriginal: @Sendable () async throws -> Void

    init(
        isEditable: Bool,
        isSupported: Bool = true,
        existingAdjustmentFormatIdentifier: String?,
        sourceModificationDate: Date? = nil,
        pixelArea: Int64 = 0,
        loadOriginal: @escaping @Sendable () async throws -> (image: CIImage, exifOrientation: Int32),
        saveEnhanced: @escaping @Sendable (
            CIImage,
            AutoEnhancementRenderer.AppliedRecipe,
            Data
        ) async throws -> Void,
        revertToOriginal: @escaping @Sendable () async throws -> Void
    ) {
        self.isEditable = isEditable
        self.isSupported = isSupported
        self.existingAdjustmentFormatIdentifier = existingAdjustmentFormatIdentifier
        self.sourceModificationDate = sourceModificationDate
        self.pixelArea = pixelArea
        self.loadOriginal = loadOriginal
        self.saveEnhanced = saveEnhanced
        self.revertToOriginal = revertToOriginal
    }
}

/// Non-destructive auto-enhancement backed by PhotoKit content editing.
///
/// The library keeps the original, no duplicate asset is created, the edit is
/// visible in Photos and every other app, and `revertAssetContentToOriginal()`
/// is the one-step undo the requirements ask for.
public actor PhotoKitEnhancementService: PhotoEnhancementService {
    typealias AuthorizationStatusProvider = @Sendable () -> PHAuthorizationStatus
    typealias RequestBuilder = @Sendable (
        String,
        PhotoEnhancementRequestPurpose
    ) async -> ResolvedPhotoEnhancementRequest?

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

    public func availability(localIdentifier: String) async -> PhotoEnhancementAvailability {
        guard (try? authorize()) != nil else { return .unavailable }
        guard let request = await requestBuilder(localIdentifier, .availability) else {
            return .unavailable
        }
        guard request.isEditable, request.isSupported else { return .unavailable }

        switch request.existingAdjustmentFormatIdentifier {
        case PhotoEnhancementAdjustment.formatIdentifier:
            return .enhanced
        case .none:
            // Our edit is gone — reverted in Photos, or never there. The cached
            // marker has to go with it, or the score cache would keep serving
            // pre-edit signals for a photo that no longer carries our edit.
            await setEnhancedFlag(false, localIdentifier: localIdentifier)
            return .available
        default:
            // Someone else's edit is on this photo. The action stays available,
            // but the UI has to say what applying it would replace — and our
            // marker is stale for the same reason as above.
            await setEnhancedFlag(false, localIdentifier: localIdentifier)
            return .editedElsewhere
        }
    }

    public func renderPreview(localIdentifier: String, targetSize: CGSize) async throws -> CGImage {
        let request = try await editableRequest(for: localIdentifier)
        let original = try await loadOriginal(with: request)
        let enhanced = renderer.render(
            // The preview is for looking at, so it is rotated the way Photos
            // would show it.
            original.image.oriented(forExifOrientation: original.exifOrientation),
            allowsSharpening: await allowsSharpening(localIdentifier: localIdentifier)
        ).image
        guard let preview = renderer.makePreview(of: enhanced, targetSize: targetSize) else {
            throw PhotoEnhancementError.renderFailed
        }
        return preview
    }

    public func applyEnhancement(
        localIdentifier: String,
        replacingOtherEdits: Bool = false
    ) async throws -> PhotoEnhancementAdjustment {
        var request = try await editableRequest(for: localIdentifier)
        if let existing = request.existingAdjustmentFormatIdentifier,
           existing != PhotoEnhancementAdjustment.formatIdentifier {
            // PhotoKit hands back the untouched original for any adjustment we
            // claim to understand, so applying here drops the other app's work.
            // That is the user's call to make, not ours to make silently.
            guard replacingOtherEdits else {
                throw PhotoEnhancementError.editedInAnotherApp
            }
            // Clear the other app's edit through the library's own undo before
            // writing ours. Layering a rendering on top of a foreign adjustment
            // is what Photos rejects as an invalid resource — and when that
            // adjustment's rendering is missing entirely (a half-synced edit
            // from another device), there is nothing to layer onto at all.
            AppLog.photoKit.debug(
                "\(AppLog.tag(.photokit, "Reverting a foreign edit before enhancing: \(existing)"))"
            )
            try await revert(with: request)
            request = try await editableRequest(for: localIdentifier)
        }
        let original = try await loadOriginal(with: request)
        let rendered = renderer.render(
            original.image,
            allowsSharpening: await allowsSharpening(localIdentifier: localIdentifier)
        )

        let encodedAdjustment: Data
        do {
            encodedAdjustment = try JSONEncoder().encode(rendered.adjustment)
        } catch {
            throw PhotoEnhancementError.renderFailed
        }

        // Measure the untouched original first when nothing is cached: after
        // the edit there is no way back to the pre-enhancement signals, and the
        // flag below is what stops the enhanced pixels from being scored.
        await cachePreEnhancementScoreIfMissing(
            localIdentifier: localIdentifier,
            original: original.image,
            request: request
        )

        do {
            try await request.saveEnhanced(rendered.image, rendered.recipe, encodedAdjustment)
        } catch let error as PhotoEnhancementError {
            AppLog.photoKit.error(
                "\(AppLog.tag(.error, "Enhancement save failed: \(Self.describe(error))"))"
            )
            throw error
        } catch {
            AppLog.photoKit.error(
                "\(AppLog.tag(.error, "Enhancement save failed: \(Self.describe(error))"))"
            )
            throw PhotoEnhancementError.saveFailed
        }

        // Scoring must keep measuring the original: our own edit may not lift
        // the Best Shot score or hide the defects it was ranked on.
        await setEnhancedFlag(true, localIdentifier: localIdentifier)
        return rendered.adjustment
    }

    public func revertToOriginal(localIdentifier: String) async throws {
        // Reverting is the library's own operation: it needs no Live Photo
        // input and no renderer, so an asset Alike can no longer enhance can
        // still be put back the way it was.
        let request = try await editableRequest(for: localIdentifier, requiresRenderSupport: false)
        guard request.existingAdjustmentFormatIdentifier == PhotoEnhancementAdjustment.formatIdentifier else {
            throw PhotoEnhancementError.notEnhancedByAlike
        }

        try await revert(with: request)
        await setEnhancedFlag(false, localIdentifier: localIdentifier)
    }

    // MARK: - Helpers

    /// Resolves for an edit. `requiresRenderSupport` is false for reverting,
    /// which needs nothing but the library's own undo.
    private func editableRequest(
        for localIdentifier: String,
        requiresRenderSupport: Bool = true
    ) async throws -> ResolvedPhotoEnhancementRequest {
        try authorize()
        guard let request = await requestBuilder(localIdentifier, .editing) else {
            throw PhotoEnhancementError.originalUnavailable
        }
        guard !requiresRenderSupport || request.isSupported else {
            throw PhotoEnhancementError.unsupportedAsset
        }
        guard request.isEditable else {
            throw PhotoEnhancementError.limitedAccessNotEditable
        }
        return request
    }

    private func revert(with request: ResolvedPhotoEnhancementRequest) async throws {
        do {
            try await request.revertToOriginal()
        } catch let error as PhotoEnhancementError {
            throw error
        } catch {
            AppLog.photoKit.error(
                "\(AppLog.tag(.error, "Revert failed: \(Self.describe(error))"))"
            )
            throw PhotoEnhancementError.saveFailed
        }
    }

    private func loadOriginal(
        with request: ResolvedPhotoEnhancementRequest
    ) async throws -> (image: CIImage, exifOrientation: Int32) {
        do {
            return try await request.loadOriginal()
        } catch let error as PhotoEnhancementError {
            throw error
        } catch {
            throw PhotoEnhancementError.originalUnavailable
        }
    }

    /// Spells out the underlying failure — a `PhotoEnhancementError` alone
    /// cannot say whether PhotoKit refused the save or the file could not be
    /// written, and that difference is the whole diagnosis on a device.
    static func describe(_ error: Error) -> String {
        if let enhancementError = error as? PhotoEnhancementError {
            return "\(enhancementError)"
        }
        let nsError = error as NSError
        var described = "\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)"
        if let debugDescription = nsError.userInfo[NSDebugDescriptionErrorKey] as? String {
            described += " debug=\(debugDescription)"
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            described += " underlying=\(underlying.domain)/\(underlying.code) \(underlying.localizedDescription)"
        }
        let extraKeys = nsError.userInfo.keys
            .filter { $0 != NSDebugDescriptionErrorKey && $0 != NSUnderlyingErrorKey }
            .sorted()
        if !extraKeys.isEmpty {
            described += " keys=\(extraKeys.joined(separator: ","))"
        }
        return described
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
        // The frame-level value, never the subject blend: the ROI is sampled on
        // its own, larger grid, so comparing it against a frame-calibrated
        // floor would refuse sharpening to every portrait.
        return score.signals.globalSharpness >= config.absoluteSharpnessFloor
    }

    /// Writes the signals of the original into the score cache when the asset
    /// was never analyzed, so `setEnhancedFlag` has a row to mark and the
    /// analyzer keeps comparing pre-enhancement measurements.
    private func cachePreEnhancementScoreIfMissing(
        localIdentifier: String,
        original: CIImage,
        request: ResolvedPhotoEnhancementRequest
    ) async {
        guard let qualityScoreRepository else { return }
        let stored = try? await qualityScoreRepository.loadScores(localIdentifiers: [localIdentifier])
        guard stored?[localIdentifier] == nil else { return }

        guard let analysisImage = renderer.makePreview(
            of: original,
            targetSize: CGSize(
                width: config.analysisImageLongSide,
                height: config.analysisImageLongSide
            )
        ) else {
            return
        }

        let signals = PhotoQualityAnalysisService(config: config)
            .signals(for: analysisImage, pixelArea: request.pixelArea)
        do {
            try await qualityScoreRepository.saveScores([
                PhotoQualityScore(
                    localIdentifier: localIdentifier,
                    sourceModificationDate: request.sourceModificationDate,
                    scoringModelVersion: config.scoringModelVersion,
                    thumbnailConfigVersion: config.thumbnailConfigVersion,
                    signals: signals
                )
            ])
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to cache pre-enhancement signals: \(Self.describe(error))"))"
            )
        }
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
    static func defaultRequestBuilder(
        localIdentifier: String,
        purpose: PhotoEnhancementRequestPurpose
    ) async -> ResolvedPhotoEnhancementRequest? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        let options = PHContentEditingInputRequestOptions()
        // Accepting any adjustment data is what makes the library hand back the
        // untouched original plus whatever edit is currently applied.
        options.canHandleAdjustmentData = { _ in true }
        // Merely deciding whether to offer the action must never pull a
        // full-size original down from iCloud; only a real edit may.
        options.isNetworkAccessAllowed = purpose == .editing

        // PhotoKit's editing input is not Sendable, but it is only ever touched
        // inside these closures, one at a time, on the caller's task.
        let requested = await requestContentEditingInput(for: asset, options: options)
        guard let editingInput = requested.input else {
            AppLog.photoKit.debug(
                """
                \(AppLog.tag(.photokit, """
                Enhancement input unavailable purpose=\(purpose) inCloud=\(requested.isInCloud)
                """))
                """
            )
            // Deciding whether to offer the action must not depend on a photo
            // being resolvable without the network: answer from the asset and
            // let the edit itself fetch what it needs.
            guard purpose == .availability else { return nil }
            return ResolvedPhotoEnhancementRequest(
                isEditable: asset.canPerform(.content),
                isSupported: asset.mediaType == .image,
                existingAdjustmentFormatIdentifier: nil,
                sourceModificationDate: asset.modificationDate,
                pixelArea: Int64(asset.pixelWidth) * Int64(asset.pixelHeight),
                loadOriginal: { throw PhotoEnhancementError.originalUnavailable },
                saveEnhanced: { _, _, _ in throw PhotoEnhancementError.originalUnavailable },
                revertToOriginal: { throw PhotoEnhancementError.originalUnavailable }
            )
        }

        let renderer = AutoEnhancementRenderer()
        let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
        // A live asset needs its Live Photo input to be *edited*, but that input
        // is only delivered on the editing pass — judging availability by it
        // would hide the action from every Live Photo.
        let isSupported = asset.mediaType == .image
            && (purpose == .availability || !isLivePhoto || editingInput.value.livePhoto != nil)

        AppLog.photoKit.debug(
            """
            \(AppLog.tag(.photokit, """
            Enhancement input ready live=\(isLivePhoto) supported=\(isSupported) \
            editable=\(asset.canPerform(.content)) \
            source=\(editingInput.value.fullSizeImageURL?.pathExtension ?? "none")
            """))
            """
        )

        return ResolvedPhotoEnhancementRequest(
            isEditable: asset.canPerform(.content),
            isSupported: isSupported,
            existingAdjustmentFormatIdentifier: editingInput.value.adjustmentData?.formatIdentifier,
            sourceModificationDate: asset.modificationDate,
            pixelArea: Int64(asset.pixelWidth) * Int64(asset.pixelHeight),
            loadOriginal: {
                let input = editingInput.value
                guard let url = input.fullSizeImageURL,
                      let image = CIImage(contentsOf: url) else {
                    throw PhotoEnhancementError.originalUnavailable
                }
                // Returned unrotated on purpose. Photos stores the rendered
                // resource in the original's pixel geometry and applies the
                // orientation itself; baking the rotation in swaps width and
                // height, and the library rejects the resource as invalid.
                return (image, input.fullSizeImageOrientation)
            },
            saveEnhanced: { image, recipe, adjustmentData in
                let input = editingInput.value
                let output = PHContentEditingOutput(contentEditingInput: input)
                output.adjustmentData = PHAdjustmentData(
                    formatIdentifier: PhotoEnhancementAdjustment.formatIdentifier,
                    formatVersion: PhotoEnhancementAdjustment.formatVersion,
                    data: adjustmentData
                )

                if input.livePhoto != nil {
                    // A Live Photo has to be written through its own editing
                    // context, so the still and every video frame carry the
                    // same grade and the asset stays a Live Photo.
                    try await saveLivePhoto(
                        input: input,
                        output: output,
                        recipe: recipe,
                        renderer: renderer
                    )
                } else {
                    do {
                        try renderer.write(image, to: output.renderedContentURL)
                    } catch {
                        AppLog.photoKit.error(
                            "\(AppLog.tag(.error, "Rendered file write failed: \(describe(error))"))"
                        )
                        throw PhotoEnhancementError.renderFailed
                    }
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

    /// Applies the recipe to the still and to every video frame, then writes
    /// the pair into `output` — the only way to keep a Live Photo alive through
    /// an edit, and still revertible.
    static func saveLivePhoto(
        input: PHContentEditingInput,
        output: PHContentEditingOutput,
        recipe: AutoEnhancementRenderer.AppliedRecipe,
        renderer: AutoEnhancementRenderer
    ) async throws {
        guard let context = PHLivePhotoEditingContext(livePhotoEditingInput: input) else {
            throw PhotoEnhancementError.unsupportedAsset
        }
        context.frameProcessor = { frame, _ in
            renderer.apply(recipe, to: frame.image)
        }

        let editingContext = UncheckedSendableBox(context)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                editingContext.value.saveLivePhoto(to: output) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: PhotoEnhancementError.renderFailed)
                    }
                }
            }
        } onCancel: {
            editingContext.value.cancel()
        }
    }

    static func requestContentEditingInput(
        for asset: PHAsset,
        options: PHContentEditingInputRequestOptions
    ) async -> (input: UncheckedSendableBox<PHContentEditingInput>?, isInCloud: Bool) {
        await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, info in
                let isInCloud = (info[PHContentEditingInputResultIsInCloudKey] as? Bool) ?? false
                continuation.resume(
                    returning: (input.map(UncheckedSendableBox.init), isInCloud)
                )
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
