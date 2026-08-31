import Foundation
import Photos

/// Minimal `PHAsset` stand-in.
///
/// The analysis services only read an asset's identity and geometry before
/// handing it to an injected image provider, so overriding those properties is
/// enough to exercise them without a photo library.
final class TestPHAsset: PHAsset {
    private let identifier: String
    private let modified: Date?
    private let width: Int
    private let height: Int

    init(
        identifier: String,
        modificationDate: Date? = Date(timeIntervalSince1970: 1_000),
        pixelWidth: Int = 4_000,
        pixelHeight: Int = 3_000
    ) {
        self.identifier = identifier
        self.modified = modificationDate
        self.width = pixelWidth
        self.height = pixelHeight
        super.init()
    }

    override var localIdentifier: String { identifier }
    override var modificationDate: Date? { modified }
    override var pixelWidth: Int { width }
    override var pixelHeight: Int { height }
}
