# SQIM-Related Logging Policy

Apply this only when implementing Alike source code that handles SQIM-related lifecycle events or errors.

- Use `Packages/Core/Sources/Core/Logging/AppLog.swift`.
- Log start, success, and failure with the closest existing `AppLog` category; add a focused category only when the integration truly needs one.
- Use structured, privacy-aware metadata.
- Never log authentication codes, Apple signing credentials, provisioning data, full local paths, IPA contents, or tokenized SQIM install URLs.
- Do not add runtime `print` calls for production diagnostics.
- Keep SQIM CLI and Xcode build output in the terminal; quote only the minimum relevant error in the user-facing result.
