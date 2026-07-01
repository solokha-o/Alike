# Logging Policy Reference

Apply this reference whenever a skill governs service/backend/repository creation.

## Required Logging Stack

- `Packages/Core/Sources/Core/Logging/AppLog.swift`

## Required Events

- Start event for the operation/flow
- Success completion event
- Failure event with safe metadata

## Data Safety Rules

- Use structured metadata instead of raw dumps.
- Redact or omit phone/email/token-like values.
- Prefer the existing `AppLog` categories and tags instead of ad hoc logger creation.
- Never use runtime `print` for production diagnostics.
