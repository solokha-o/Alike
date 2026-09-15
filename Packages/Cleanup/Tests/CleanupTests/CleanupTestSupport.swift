import Photos

/// `PhotoCluster` holds `PHAsset` values that cannot be constructed directly, so the
/// tests use a subclass that only reports the properties under test.
final class FakePhotoAsset: PHAsset, @unchecked Sendable {
    private let identifierOverride: String
    private let favoriteOverride: Bool
    private let pixelWidthOverride: Int
    private let pixelHeightOverride: Int

    /// A fake has no PhotoKit resources, so `estimatedCleanupBytes` falls back to the
    /// pixel heuristic: `pixelWidth`/`pixelHeight` drive it (`max(1, w * h / 2)`),
    /// so a test that cares about bytes sets them; the default keeps every asset at 1.
    init(
        localIdentifier: String = UUID().uuidString,
        isFavorite: Bool = false,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0
    ) {
        identifierOverride = localIdentifier
        favoriteOverride = isFavorite
        pixelWidthOverride = pixelWidth
        pixelHeightOverride = pixelHeight
        super.init()
    }

    override var localIdentifier: String { identifierOverride }
    override var isFavorite: Bool { favoriteOverride }
    override var pixelWidth: Int { pixelWidthOverride }
    override var pixelHeight: Int { pixelHeightOverride }
}
