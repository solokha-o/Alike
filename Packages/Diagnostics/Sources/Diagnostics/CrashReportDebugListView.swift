#if DEBUG
import Core
import SwiftUI

/// Developer tooling: every stored crash payload, with a way to get it off the device
/// and a way to fake one. Never shipped, so its labels are plain literals.
public struct CrashReportDebugListView: View {
    private let store: CrashReportStore
    @State private var rows: [Row] = []

    private struct Row: Identifiable {
        let report: CrashReport
        let fileURL: URL?
        var id: UUID { report.id }
    }

    public init(store: CrashReportStore = .shared) {
        self.store = store
    }

    public var body: some View {
        List {
            Section {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(row.report.appVersion ?? "?") (\(row.report.appBuild ?? "?")) — \(row.report.promptState.rawValue)")
                        Text("\(row.report.osVersion ?? "?") — \(row.report.deviceModel ?? "?")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(row.report.receivedAt.alikeFormatted(date: .numeric, time: .standard))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let fileURL = row.fileURL {
                            ShareLink("Share payload", item: fileURL)
                                .font(.footnote)
                        }
                    }
                }
            } footer: {
                Text("Newest \(CrashReportStore.defaultMaxReports) payloads are kept. Symbolicate with tools/symbolicate <payload.json>.")
            }

            Section {
                Button("Inject fixture payload") {
                    Task {
                        await store.ingest([Self.fixturePayload])
                        await reload()
                    }
                }
            } footer: {
                Text("Stored as pending: the prompt appears at the next calm moment on the Scanner tab.")
            }
        }
        .navigationTitle(Text("Crash Reports"))
        .task { await reload() }
    }

    private func reload() async {
        var loaded: [Row] = []
        for report in await store.reports().reversed() {
            loaded.append(Row(report: report, fileURL: await store.payloadFileURL(for: report.id)))
        }
        rows = loaded
    }

    /// The shape `MXDiagnosticPayload.jsonRepresentation()` produces, cut down to one frame.
    private static var fixturePayload: Data {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return Data(
            """
            {"timeStampBegin":"2026-01-01 00:00:00","timeStampEnd":"2026-01-01 23:59:00",\
            "crashDiagnostics":[{"version":"1.0.0","diagnosticMetaData":{"appBuildVersion":"\(build)",\
            "appVersion":"\(version)","osVersion":"iPhone OS 18.6 (22G86)","deviceType":"\(DeviceModel.identifier)",\
            "bundleIdentifier":"com.alike.app","exceptionType":1,"exceptionCode":0,"signal":11,\
            "terminationReason":"Namespace SIGNAL, Code 11 Segmentation fault: 11"},\
            "callStackTree":{"callStackPerThread":true,"callStacks":[{"threadAttributed":true,\
            "callStackRootFrames":[{"binaryUUID":"00000000-0000-0000-0000-000000000000",\
            "offsetIntoBinaryTextSegment":1318192,"sampleCount":1,"binaryName":"Alike","address":4302655792}]}]}}]}
            """.utf8
        )
    }
}
#endif
