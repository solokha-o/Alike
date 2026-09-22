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

    private let directoryURL: URL
    private let fileManager: FileManager
    private let maxReports: Int
    private var changeObservers: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        maxReports: Int = CrashReportStore.defaultMaxReports
    ) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.fileManager = fileManager
        self.maxReports = max(1, maxReports)
    }

    // MARK: - Change notifications

    /// Yields after every change to the stored reports.
    ///
    /// A fresh stream per call, because the store outlives its observers: the screen
    /// that watches it is torn down and rebuilt in the same process, and one shared
    /// stream would be finished for good by the first observer's cancellation.
    public func changes() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeChangeObserver(id) }
        }
        changeObservers[id] = continuation
        return stream
    }

    private func removeChangeObserver(_ id: UUID) {
        changeObservers[id] = nil
    }

    private func notifyChange() {
        for continuation in changeObservers.values {
            continuation.yield()
        }
    }

    // MARK: - Reading

    /// Oldest first. Empty for an index written by a newer schema; a missing or corrupt
    /// index is rebuilt from the payload files rather than read as "no reports", so a
    /// payload that outlived its index entry is still visible.
    public func reports() -> [CrashReport] {
        switch loadIndex() {
        case .loaded(let index): index.reports
        case .missing, .corrupt: rebuiltReports()
        case .newerSchema: []
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
            let header = try? Self.decoder.decode(CrashReportIndexHeader.self, from: data)
        else {
            AppLog.diagnostics.error("\(AppLog.tag(.error, "Crash report index could not be decoded."))")
            return .corrupt
        }
        // The version decides before the records do: a newer schema may have reshaped
        // everything below it, and failing to decode that is not corruption.
        guard header.schemaVersion <= CrashReportIndex.currentSchemaVersion else {
            AppLog.diagnostics.notice("Crash report index schema \(header.schemaVersion) is newer than this build.")
            return .newerSchema
        }
        guard let index = try? Self.decoder.decode(CrashReportIndex.self, from: data) else {
            AppLog.diagnostics.error("\(AppLog.tag(.error, "Crash report index could not be decoded."))")
            return .corrupt
        }
        return .loaded(index)
    }

    /// `nil` when a newer build owns the index: this build must not rewrite a shape it
    /// cannot read, so it leaves the directory alone.
    private func reportsForWriting() -> [CrashReport]? {
        switch loadIndex() {
        case .loaded(let index): index.reports
        case .missing, .corrupt: rebuiltReports()
        case .newerSchema: nil
        }
    }

    /// Recovers a record per payload file when the index is unreadable. Recovered
    /// records are `prompted`: whether the user was already asked is unknown, and
    /// asking twice is the worse mistake.
    private func rebuiltReports() -> [CrashReport] {
        Self.sorted(payloadFiles().compactMap(recoveredReport(fromPayloadAt:)))
    }

    /// Records for payload files the index does not name.
    ///
    /// `ingest` writes the payload first and the index second, so a kill or a failed
    /// index write leaves the only copy of a report on disk and unlisted. Adopting it
    /// is what keeps it: the alternative is deleting the one thing MetricKit will
    /// never hand over again.
    private func adoptedOrphans(notIn known: Set<UUID>) -> [CrashReport] {
        payloadFiles().compactMap { url in
            guard
                let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                !known.contains(id)
            else { return nil }
            return recoveredReport(fromPayloadAt: url)
        }
    }

    private func recoveredReport(fromPayloadAt url: URL) -> CrashReport? {
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

    /// Slots each orphan into the existing order rather than re-sorting around it.
    ///
    /// MetricKit hands over a whole batch under one `receivedAt`, so sorting the list
    /// would order those by their random UUIDs and let rotation drop an arbitrary one
    /// of them. The recorded order is the arrival order and stays as it is.
    private static func merged(_ reports: [CrashReport], with orphans: [CrashReport]) -> [CrashReport] {
        guard !orphans.isEmpty else { return reports }
        var merged = reports
        for orphan in sorted(orphans) {
            let position = merged.firstIndex { !isOlder($0, than: orphan) } ?? merged.count
            merged.insert(orphan, at: position)
        }
        return merged
    }

    private static func sorted(_ reports: [CrashReport]) -> [CrashReport] {
        reports.sorted { isOlder($0, than: $1) }
    }

    private static func isOlder(_ report: CrashReport, than other: CrashReport) -> Bool {
        (report.receivedAt, report.id.uuidString) < (other.receivedAt, other.id.uuidString)
    }

    /// Adopts any payload file the index does not name, trims to the newest
    /// `maxReports`, writes the index, then deletes the files rotation just dropped.
    ///
    /// Deleting by the dropped list rather than by "not in the index" is the point: a
    /// payload written while the index write was interrupted is taken in instead of
    /// being swept away, and a file this store never accounted for is left alone.
    private func save(_ reports: [CrashReport]) {
        let known = Self.merged(reports, with: adoptedOrphans(notIn: Set(reports.map(\.id))))
        let kept = Array(known.suffix(maxReports))
        do {
            let data = try Self.encoder.encode(CrashReportIndex(reports: kept))
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            AppLog.diagnostics.error("\(AppLog.tag(.error, "Crash report index not written: \(error)"))")
            return
        }
        let dropped = Set(known.map(\.id)).subtracting(kept.map(\.id))
        for url in payloadFiles() {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  dropped.contains(id)
            else { continue }
            try? fileManager.removeItem(at: url)
        }
        notifyChange()
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
