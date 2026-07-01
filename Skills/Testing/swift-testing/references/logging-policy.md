# Logging Policy for Tests

Apply when tests cover services/repositories using project logging.

## Required Stack

- `Packages/Core/Sources/Core/Logging/AppLog.swift`

## Rules

- Prefer metadata assertions over full formatted-message comparisons.
- Avoid raw PII in test logs; use redaction helpers.
- Avoid `print` in reusable test utilities.
- If a test inspects log side effects, isolate that behavior so parallel tests do
  not interfere with shared logger state.
