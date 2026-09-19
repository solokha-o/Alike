import Foundation

/// What a MetricKit diagnostic payload says about the build and device that crashed.
///
/// Read leniently from the payload JSON: Apple owns that format and may change it
/// between iOS versions, so every field is optional and a payload that does not parse
/// simply yields an empty value.
struct CrashPayloadMetadata: Equatable, Sendable {
    var appVersion: String?
    var appBuild: String?
    var osVersion: String?
    var deviceModel: String?

    init(payload: Data) {
        guard
            let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let crashes = root["crashDiagnostics"] as? [[String: Any]],
            let metaData = crashes.lazy.compactMap({ $0["diagnosticMetaData"] as? [String: Any] }).first
        else { return }
        appVersion = metaData["appVersion"] as? String
        appBuild = metaData["appBuildVersion"] as? String
        osVersion = metaData["osVersion"] as? String
        deviceModel = metaData["deviceType"] as? String
    }
}
