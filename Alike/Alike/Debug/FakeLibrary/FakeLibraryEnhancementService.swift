#if DEBUG && !targetEnvironment(simulator)
import Core
import CoreGraphics

/// Enhancement for a fake library on a device: never offered, never written.
///
/// On a device the fake groups hold the user's own newest photos, so the real
/// `PhotoKitEnhancementService` would edit them. On the simulator the groups hold
/// only the drawn album photos, and the real service is used there.
nonisolated struct FakeLibraryEnhancementService: PhotoEnhancementService {
    func availability(localIdentifier _: String) async -> PhotoEnhancementAvailability {
        .unavailable
    }

    func renderPreview(localIdentifier _: String, targetSize _: CGSize) async throws -> CGImage {
        throw PhotoEnhancementError.renderFailed
    }

    func applyEnhancement(
        localIdentifier _: String,
        replacingOtherEdits _: Bool
    ) async throws -> PhotoEnhancementAdjustment {
        throw PhotoEnhancementError.saveFailed
    }

    func revertToOriginal(localIdentifier _: String) async throws {
        throw PhotoEnhancementError.saveFailed
    }
}
#endif
