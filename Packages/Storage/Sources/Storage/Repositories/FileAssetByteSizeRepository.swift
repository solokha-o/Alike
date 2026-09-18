import Core
import Foundation

/// JSON-backed cache of measured asset byte sizes.
///
/// Disposable: a missing, corrupt or other-unit file loads as empty and the sizes
/// are measured again. It holds no user decision, so it is never migrated.
public actor FileAssetByteSizeRepository: AssetByteSizeRepository {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    public func loadAll() -> [AssetByteSizeRecord] {
        loadPayload()?.records ?? []
    }

    public func replaceAll(_ records: [AssetByteSizeRecord]) throws {
        try write(records: records, libraryTotalBytes: loadPayload()?.libraryTotalBytes)
    }

    // `async` like the requirement: a synchronous witness would lose overload
    // resolution to the protocol's default when called on the concrete type.
    public func loadLibraryTotalBytes() async -> Int64? {
        loadPayload()?.libraryTotalBytes
    }

    public func saveLibraryTotalBytes(_ bytes: Int64?) async throws {
        try write(records: loadPayload()?.records ?? [], libraryTotalBytes: bytes)
    }

    /// `nil` when the file is missing, unreadable or was written in another unit.
    private func loadPayload() -> AssetByteSizePayload? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let payload = try decoder.decode(AssetByteSizePayload.self, from: Data(contentsOf: fileURL))
            return payload.byteSizeVersion == AssetByteSize.currentVersion ? payload : nil
        } catch {
            AppLog.storage.error(
                "\(AppLog.tag(.error, "Failed to load asset byte sizes: \(error.localizedDescription)"))"
            )
            return nil
        }
    }

    private func write(records: [AssetByteSizeRecord], libraryTotalBytes: Int64?) throws {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        let payload = AssetByteSizePayload(
            byteSizeVersion: AssetByteSize.currentVersion,
            records: records,
            libraryTotalBytes: libraryTotalBytes
        )
        try encoder.encode(payload).write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Alike", isDirectory: true)
            .appendingPathComponent("asset_byte_sizes.json", isDirectory: false)
    }
}

private struct AssetByteSizePayload: Codable {
    let byteSizeVersion: Int
    let records: [AssetByteSizeRecord]
    /// Absent from files written before 1.5.0.
    var libraryTotalBytes: Int64?
}
