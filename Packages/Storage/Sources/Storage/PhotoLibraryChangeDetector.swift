import Core
import Foundation
import Photos

/// What happened to the photo library between a stored change token and now.
public struct PhotoLibraryChangeSummary: Equatable, Sendable {
    /// Assets inserted since the token that are still present and are images.
    public let insertedImageCount: Int
    /// Whether any asset was removed since the token. Deleted assets can no
    /// longer be fetched, so their media type is unknowable here; callers pair
    /// this with an image-count comparison rather than trusting it alone.
    public let hasDeletions: Bool

    public init(insertedImageCount: Int, hasDeletions: Bool) {
        self.insertedImageCount = insertedImageCount
        self.hasDeletions = hasDeletions
    }

    public static let none = PhotoLibraryChangeSummary(
        insertedImageCount: 0,
        hasDeletions: false
    )
}

/// Reads library membership changes without interpreting them, so the decision
/// to prompt for a rescan stays testable without a real photo library.
public protocol PhotoLibraryChangeDetecting: Sendable {
    /// Archived `PHPersistentChangeToken` for the library's current state.
    func currentToken() -> Data?

    /// Number of image assets currently visible to the app.
    func imageAssetCount() -> Int

    /// Membership changes since `token`, or `nil` when the question cannot be
    /// answered — an expired token, an unreadable archive, or a library the app
    /// cannot query. `nil` means "fall back", never "changed".
    func changes(since token: Data) -> PhotoLibraryChangeSummary?
}

/// PhotoKit-backed implementation using persistent change history.
///
/// Membership changes are the only signal used. `PHAsset.modificationDate`
/// deliberately is not: iCloud sync, favouriting, edits, system re-analysis and
/// the app's own originals download all bump it, which made every scan look
/// like the library had gained new photos the moment it finished.
public struct PhotoKitChangeDetector: PhotoLibraryChangeDetecting {
    public init() {}

    public func currentToken() -> Data? {
        archive(PHPhotoLibrary.shared().currentChangeToken)
    }

    public func imageAssetCount() -> Int {
        PHAsset.fetchAssets(with: .image, options: nil).count
    }

    public func changes(since token: Data) -> PhotoLibraryChangeSummary? {
        guard let changeToken = unarchive(token) else { return nil }

        let fetchResult: PHPersistentChangeFetchResult
        do {
            fetchResult = try PHPhotoLibrary.shared().fetchPersistentChanges(since: changeToken)
        } catch {
            AppLog.storage.debug(
                "\(AppLog.tag(.storage, "Persistent change history unavailable: \(error.localizedDescription)"))"
            )
            return nil
        }

        let detailsProviders = fetchResult.map { change in
            { () throws -> AssetChangeDetails in
                let details = try change.changeDetails(for: .asset)
                return AssetChangeDetails(
                    insertedLocalIdentifiers: details.insertedLocalIdentifiers,
                    deletedLocalIdentifiers: details.deletedLocalIdentifiers
                )
            }
        }

        guard var accumulated = Self.accumulateAssetChanges(detailsProviders) else { return nil }

        // An asset inserted and then deleted again is not a change the user
        // needs to rescan for.
        accumulated.inserted.subtract(accumulated.deleted)

        return PhotoLibraryChangeSummary(
            insertedImageCount: imageAssetCount(among: accumulated.inserted),
            hasDeletions: !accumulated.deleted.isEmpty
        )
    }

    /// Local identifiers touched by one persistent-history change, mirroring
    /// the fields of `PHPersistentObjectChangeDetails` without the PhotoKit
    /// type — that type has no public initializer, so this is what lets the
    /// accumulation logic below run against fakes in tests.
    struct AssetChangeDetails: Equatable, Sendable {
        let insertedLocalIdentifiers: Set<String>
        let deletedLocalIdentifiers: Set<String>
    }

    /// Folds per-change asset details into inserted/deleted identifier sets.
    /// Returns nil the moment a change's details can't be read, matching the
    /// detector's contract of nil meaning "cannot answer" — a throwing
    /// record must not be treated as if it held no changes, since it could
    /// be the only insertion or deletion in the batch.
    static func accumulateAssetChanges(
        _ detailsProviders: [() throws -> AssetChangeDetails]
    ) -> (inserted: Set<String>, deleted: Set<String>)? {
        var insertedIdentifiers: Set<String> = []
        var deletedIdentifiers: Set<String> = []

        for provider in detailsProviders {
            guard let details = try? provider() else { return nil }
            insertedIdentifiers.formUnion(details.insertedLocalIdentifiers)
            deletedIdentifiers.formUnion(details.deletedLocalIdentifiers)
        }

        return (insertedIdentifiers, deletedIdentifiers)
    }

    private func imageAssetCount(among identifiers: Set<String>) -> Int {
        guard !identifiers.isEmpty else { return 0 }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return PHAsset.fetchAssets(
            withLocalIdentifiers: Array(identifiers),
            options: fetchOptions
        ).count
    }

    private func archive(_ token: PHPersistentChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private func unarchive(_ data: Data) -> PHPersistentChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data)
    }
}
