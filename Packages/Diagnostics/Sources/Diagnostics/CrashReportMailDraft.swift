import Foundation

/// Everything the crash report email is made of, decided without any UI so it can be
/// tested. The user sees and sends the email themselves; the app opens no connection.
public struct CrashReportMailDraft: Equatable, Sendable {
    /// Stands in for whatever the payload does not say about the crashed build.
    public struct Fallback: Equatable, Sendable {
        public var appVersion: String
        public var appBuild: String
        public var osVersion: String
        public var deviceModel: String

        public init(appVersion: String, appBuild: String, osVersion: String, deviceModel: String) {
            self.appVersion = appVersion
            self.appBuild = appBuild
            self.osVersion = osVersion
            self.deviceModel = deviceModel
        }

        public static var current: Fallback {
            let info = Bundle.main.infoDictionary
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return Fallback(
                appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
                appBuild: info?["CFBundleVersion"] as? String ?? "?",
                osVersion: "iOS \(os.majorVersion).\(os.minorVersion)",
                deviceModel: DeviceModel.identifier
            )
        }
    }

    public struct Attachment: Equatable, Sendable {
        public let fileURL: URL
        public let fileName: String
        public static let mimeType = "application/json"
    }

    public let recipient: String
    public let subject: String
    public let body: String
    public let attachments: [Attachment]

    /// - Parameter attachmentURLs: Payload files, in the order of `prompt.reports`.
    public init(
        prompt: CrashReportPrompt,
        attachmentURLs: [URL],
        body: String = DiagnosticsL10n.Mail.body,
        fallback: Fallback = .current
    ) {
        let newest = prompt.reports[0]
        recipient = CrashReportSupport.email
        subject = [
            "Alike crash \(newest.appVersion ?? fallback.appVersion) (\(newest.appBuild ?? fallback.appBuild))",
            newest.osVersion.map(Self.displayOSVersion) ?? fallback.osVersion,
            newest.deviceModel ?? fallback.deviceModel
        ].joined(separator: " — ")
        self.body = body
        attachments = attachmentURLs.enumerated().map { position, url in
            Attachment(fileURL: url, fileName: "alike-crash-\(position + 1).json")
        }
    }

    /// The message for the share sheet, which has no recipient field.
    ///
    /// `ShareLink` carries the files, the subject and this text and drops `recipient`,
    /// so without the address in here a Gmail user is handed a finished report and
    /// nowhere to send it.
    public var shareBody: String {
        "\(DiagnosticsL10n.Mail.shareRecipient)\n\(recipient)\n\n\(body)"
    }

    /// MetricKit reports `iPhone OS 18.6 (22G86)`; the subject reads `iOS 18.6`.
    static func displayOSVersion(_ raw: String) -> String {
        var version = raw
        if let build = version.range(of: " (") {
            version = String(version[..<build.lowerBound])
        }
        for prefix in ["iPhone OS ", "iPadOS ", "iOS "] where version.hasPrefix(prefix) {
            return "iOS " + version.dropFirst(prefix.count)
        }
        return version
    }
}
