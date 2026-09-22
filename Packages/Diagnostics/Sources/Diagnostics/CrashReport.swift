import Foundation

/// One crash payload MetricKit handed to the app, as recorded in the index.
///
/// The payload bytes live beside the index in `payloads/<id>.json`, untouched; this
/// record only carries what the app needs without parsing them again.
///
/// Persisted. Every field added after schema 1 must be optional or defaulted, a coding
/// key is never repurposed, and a field never changes type in place — see
/// `Skills/Storage/persisted-data-evolution`.
public struct CrashReport: Codable, Sendable, Identifiable, Equatable {
    /// Whether the user has been asked about this payload.
    ///
    /// Only `pending` ever leads to a prompt. A raw value this build does not know
    /// decodes as `prompted`, so a payload written by a newer build is never asked
    /// about twice after a downgrade.
    public enum PromptState: String, Codable, Sendable {
        case pending
        /// The sheet was on screen. Terminal on its own: closing the sheet by swipe
        /// is a refusal, and a refusal is final.
        case prompted
        case declined
        case sent

        public init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            self = PromptState(rawValue: rawValue) ?? .prompted
        }
    }

    public let id: UUID
    public let receivedAt: Date
    /// Describe the build that crashed, which is not necessarily the one running now.
    /// `nil` means the payload did not say, not an empty value.
    public var appVersion: String?
    public var appBuild: String?
    public var osVersion: String?
    public var deviceModel: String?
    public var promptState: PromptState

    public init(
        id: UUID = UUID(),
        receivedAt: Date,
        appVersion: String? = nil,
        appBuild: String? = nil,
        osVersion: String? = nil,
        deviceModel: String? = nil,
        promptState: PromptState = .pending
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.promptState = promptState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        receivedAt = try container.decode(Date.self, forKey: .receivedAt)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        appBuild = try container.decodeIfPresent(String.self, forKey: .appBuild)
        osVersion = try container.decodeIfPresent(String.self, forKey: .osVersion)
        deviceModel = try container.decodeIfPresent(String.self, forKey: .deviceModel)
        promptState = try container.decodeIfPresent(PromptState.self, forKey: .promptState) ?? .prompted
    }
}

/// Just enough of `index.json` to learn which build wrote it.
///
/// Read before the records: an index whose shape this build cannot decode at all is
/// then recognized as newer rather than corrupt, and is left alone instead of rewritten.
struct CrashReportIndexHeader: Decodable {
    var schemaVersion: Int
}

/// The on-disk envelope of `index.json`.
struct CrashReportIndex: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    /// Oldest first.
    var reports: [CrashReport]

    init(schemaVersion: Int = CrashReportIndex.currentSchemaVersion, reports: [CrashReport]) {
        self.schemaVersion = schemaVersion
        self.reports = reports
    }
}
