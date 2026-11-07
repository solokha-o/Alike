# Diagnostics

Local crash reports and the prompt that asks the user to send one.
It subscribes to MetricKit crash diagnostics, stores reports on the device, and builds a mail draft.
It also has a debug list of stored reports.

- **Category:** Foundation with UI (see `Docs/adr/0004-package-dependencies.md`)
- **Responsibility:** Collect crash reports and let the user share them by mail.
- **Main public types:** `CrashDiagnosticsSubscriber`, `CrashReportStore`, `CrashReportPromptCoordinator`, `CrashReportPromptSheet`, `CrashReportMailDraft`, `CrashReport`
- **Depends on:** Core
- **Does not do:** Send data to a server or collect analytics.
