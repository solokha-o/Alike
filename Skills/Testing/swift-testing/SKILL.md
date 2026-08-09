---
name: swift-testing
description: Fast, deterministic Swift tests with Swift Testing (@Suite, @Test, #expect), strong async patterns, and clear package-level test architecture.
---

# Swift Testing

Use this skill when the user asks to add, fix, refactor, or review tests in Swift packages/features.

## Trigger Conditions

- Write new unit/integration tests
- Migrate XCTest to Swift Testing
- Fix flaky async/concurrency tests
- Improve test speed and determinism
- Review tests for isolation/parallel safety

## Workflow

1. Identify behavior under test and smallest boundary (function/type/service).
2. Choose Swift Testing primitives: `@Suite`, `@Test`, `#expect`, `#require`.
3. Prefer deterministic inputs and explicit dependency injection.
4. For async flows, use structured async patterns (continuations/confirmations/TestClock).
5. Validate parallel safety and serialize only where shared mutable state exists.

## Decision Tree

1. Need quick syntax/usage for `@Test` and assertions?
Open `references/components.md`.

2. Working with async flows, timers, callbacks, or race-prone tests?
Open `references/async-and-concurrency.md`.

3. Migrating from XCTest or comparing approaches?
Open `references/migration-from-xctest.md`.

4. Need full legacy examples and extended notes?
Open `references/full-guide.md`.

## Guardrails

- Prefer pure/unit boundaries over UI-hosted tests when possible.
- Avoid sleeps/timeouts as primary synchronization strategy.
- Do not over-serialize suites; keep parallelism by default.
- Keep each test focused on one behavior.
- Do not use runtime `print` for diagnostics in production-facing test helpers.

## Logging Policy

- If tests touch service/repository logging behavior, keep them aligned with
  `Packages/Core/Sources/Core/Logging/AppLog.swift`.
- Avoid assertions that depend on global logger state in suites that can execute
  concurrently.
- Use safe, redacted fixture data when log messages include user-facing values.

## Related Skills

- `Skills/SwiftConcurrency/swift-concurrency-expert/SKILL.md`
- `Skills/Architecture/SwiftUIModular/SKILL.md`
- `Skills/Meta/skill-authoring-governance/SKILL.md`
