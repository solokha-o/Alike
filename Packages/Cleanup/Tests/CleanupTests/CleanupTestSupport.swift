import Photos

/// `PhotoCluster` holds `PHAsset` values that cannot be constructed directly, so the
/// tests use a subclass that only reports the properties under test.
final class FakePhotoAsset: PHAsset, @unchecked Sendable {
    private let identifierOverride: String
    private let favoriteOverride: Bool

    init(localIdentifier: String = UUID().uuidString, isFavorite: Bool = false) {
        identifierOverride = localIdentifier
        favoriteOverride = isFavorite
        super.init()
    }

    override var localIdentifier: String { identifierOverride }
    override var isFavorite: Bool { favoriteOverride }
}
