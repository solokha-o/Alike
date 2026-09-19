import Core
import Foundation

/// File-backed store for crash payloads, under `<Application Support>/Alike/Diagnostics`.
///
/// MetricKit delivers a payload once and keeps no copy, so whatever is not written here
/// is gone. Layout — a shipped contract, never reinterpreted in place:
///
///     index.json            `CrashReportIndex`: schema version + one record per payload
///     payloads/<id>.json    the payload bytes exactly as MetricKit produced them
///
/// Nothing here throws or traps. A failure is logged and degrades to "no reports",
/// because the alternative is crashing while recording a crash.
///
/// One instance per directory: two actors over the same files would race, so the
/// subscriber, the prompt and the debug screen all go through `shared`.
public actor CrashReportStore {
    public static let shared = CrashReportStore()
    public static let defaultMaxReports = 20

    /// Yields after every change to the stored reports. Single consumer.
    public nonisolated let changes: AsyncStream<Void>

    private let directoryURL: URL
    private let fileManager: FileManager
    private let maxReports: Int
    private let changeContinuation: AsyncStream<Void>.Continuation

    public init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        maxReports: Int = CrashReportStore.defaultMaxReports
    ) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.fileManager = fileManager
        self.maxReports = max(1, maxReports)
        (changes, changeContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    // MARK: - Reading

    /// Oldest first. Empty for a missing index and for one written by a newer schema;
    /// a corrupt index is rebuilt from the payload files instead of being discarded.
    public func reports() -> [CrashReport] {
        switch loadIndex() {
        case .loaded(let index): index.reports
        case .corrupt: rebuiltReports()
        case .missing, .newerSchema: []
        }
    }

    public func payloadFileURL(for id: UUID) -> URL? {
        let url = payloadURL(for: id)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Writing

    /// Stores each payload and keeps the newest `maxReports`.
    public func ingest(_ payloads: [Data], receivedAt: Date = Date()) {
        guard !payloads.isEmpty, var reports = reportsForWriting() else { return }
        do {
            try fileManager.createDirectory(at: payloadsURL, withIntermediateDirectories: true)
        } catch {
            AppLog.diagnostics.error("\(AppLog.tag(.error, "Crash payload directory unavailable: \(error)"))")
            return
        }
        for payload in payloads {
            let metadata = CrashPayloadMetadata(payload: payload)
            let report = CrashReport(
                receivedAt: receivedAt,
                appVersion: metadata.appVersion,
                appBuild: metadata.appBuild,
                osVersion: metadata.osVersion,
                deviceModel: metadata.deviceModel
            )
            do {
                try payload.write(to: payloadURL(for: report.id), options: .atomic)
                reports.append(report)
            } catch {
                AppLog.diagnostics.error("\(AppLog.tag(.error, "Crash payload not written: \(error)"))")
            }
        }
        save(reports)
    }

    public func setPromptState(_ state: CrashReport.PromptState, for id: UUID) {
        guard
            var reports = reportsForWriting(),
            let position = reports.firstIndex(where: { $0.id == id }),
            reports[position].promptState != state
        else { return }
        reports[position].promptState = state
        save(reports)
    }

    // MARK: - Index

    private enum IndexState {
        case missing
        case loaded(CrashReportIndex)
        case corrupt
        case newerSchema
    }

    private func loadIndex() -> IndexState {
        guard fileManager.fileExists(atPath: indexURL.path) else { return .missing }
        guard
            let data = try? Data(contentsOf: indexURL),
            let index = try? Self.decoder.decode(CrashReportIndex.self, from: data)
        else {
            AppLog.diagnostics.error("\(AppLog.tag(.error, "Crash report index could not be decoded."))")
            return .corrupt
        }
        guard index.schemaVersion <= CrashReportIndex.currentSchemaVersion else {
            AppLog.diagnostics.notice("Crash report index schema \(index.schemaVersion) is newer than this build.")
            return .newerSchema
        }
        return .loaded(index)
    }

    /// `nil` when a newer build owns the index: this build must not rewrite a shape it
    /// cannot read, so it leaves the directory alone.
    private func reportsForWriting() -> [CrashReport]? {
        switch loadIndex() {
        case .missing: []
        case .loaded(let index): index.reports
        case .corrupt: rebuiltReports()
        case .newerSchema: nil
        }
    }

    /// Recovers a record per payload file when the index is unreadable. Recovered
    /// records are `prompted`: whether the user was already asked is unknown, and
    /// asking twice is the worse mistake.
    private func rebuiltReports() -> [CrashReport] {
        payloadFiles()
            .compactMap { url -> CrashReport? in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                    return nil
                }
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                let metadata = (try? Data(contentsOf: url)).map(CrashPayloadMetadata.init(payload:))
                return CrashReport(
                    id: id,
                    receivedAt: modified ?? .distantPast,
                    appVersion: metadata?.appVersion,
                    appBuild: metadata?.appBuild,
                    osVersion: metadata?.osVersion,
                    deviceModel: metadata?.deviceModel,
                    promptState: .prompted
                )
            }
            .sorted { ($0.receivedAt, $0.id.uuidString) < ($1.receivedAt, $1.id.uuidString) }
    }

    /// Trims to the newest `maxReports`, writes the index, then deletes every payload
    /// file the index no longer names. Rotation only ever removes files this store
    /// wrote, and only after the index that drops them is safely on disk.
    private func save(_ reports: [CrashReport]) {
        let kept = Array(reports.suffix(maxReports))
        do {
            let data = try Self.encoder.encode(CrashReportIndex(reports: kept))
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            AppLog.diagnostics.error("\(AppLog.tag(.error, "Crash report index not written: \(error)"))")
            return
        }
        let keptIDs = Set(kept.map(\.id))
        for url in payloadFiles() {
            let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
            if id.map(keptIDs.contains) != true {
                try? fileManager.removeItem(at: url)
            }
        }
        changeContinuation.yield()
    }

    // MARK: - Paths

    private var indexURL: URL { directoryURL.appendingPathComponent("index.json", isDirectory: false) }
    private var payloadsURL: URL { directoryURL.appendingPathComponent("payloads", isDirectory: true) }

    private func payloadURL(for id: UUID) -> URL {
        payloadsURL.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private func payloadFiles() -> [URL] {
        let urls = try? fileManager.contentsOfDirectory(
            at: payloadsURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        return (urls ?? []).filter { $0.pathExtension == "json" }
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("Alike", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
