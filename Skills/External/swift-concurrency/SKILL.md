---
name: swift-concurrency
description: Diagnose Swift Concurrency issues, refactor callback-based code to async/await, and guide Swift 6 migration when local Alike concurrency guidance is not enough. Use for deep Sendable/isolation diagnostics, migration planning, or concurrency compiler/linter warnings.
---

# Swift Concurrency

Use this vendored external skill as depth after
`Skills/SwiftConcurrency/swift-concurrency-expert/SKILL.md`, not as the
default Alike router.

## Fast Path

Before proposing a fix:

1. Inspect `Package.swift` or `.pbxproj` for Swift language mode, strict concurrency, default isolation, and upcoming features.
2. Capture the exact diagnostic and offending symbol.
3. Identify the isolation boundary: `@MainActor`, custom actor, actor instance isolation, `nonisolated`, or detached/unstructured task.
4. Confirm whether the code is UI-bound or intended to run off the main actor.

Project settings that change concurrency behavior:

| Setting | SwiftPM (`Package.swift`) | Xcode (`.pbxproj`) |
|---|---|---|
| Language mode | `swiftLanguageVersions` or `-swift-version` | Swift Language Version |
| Strict concurrency | `.enableExperimentalFeature("StrictConcurrency=targeted")` | `SWIFT_STRICT_CONCURRENCY` |
| Default isolation | `.defaultIsolation(MainActor.self)` | `SWIFT_DEFAULT_ACTOR_ISOLATION` |
| Upcoming features | `.enableUpcomingFeature("NonisolatedNonsendingByDefault")` | `SWIFT_UPCOMING_FEATURE_*` |

If these settings are unknown and the fix depends on them, inspect the project before giving migration-sensitive guidance.

## Quick Fix Mode

Use Quick Fix Mode only when:

- the issue is localized to one file or one type
- the isolation boundary is clear
- the fix can be explained in 1-2 behavior-preserving steps

Skip Quick Fix Mode when:

- build settings or default isolation are unknown
- the issue crosses module boundaries
- the likely fix depends on unsafe escape hatches
- public API behavior may change

## Common Diagnostics

| Diagnostic | First check | Smallest safe fix | Reference |
|---|---|---|---|
| `Main actor-isolated ... cannot be used from a nonisolated context` | Is it truly UI-bound? | Isolate the caller or use `MainActor.run` only when ownership is correct | `references/actors.md` |
| `Actor-isolated type does not conform to protocol` | Must the requirement run on the actor? | Prefer isolated conformance; use `nonisolated` only for truly nonisolated requirements | `references/actors.md` |
| `Sending value of non-Sendable type ... risks causing data races` | What boundary is crossed? | Keep access inside one actor or transfer immutable/value data | `references/sendable.md` |
| `SwiftLint async_without_await` | Is `async` required by protocol/override/`@concurrent`? | Remove `async` or use narrow suppression with rationale | `references/linting.md` |
| `wait(...) is unavailable from asynchronous contexts` | Is this legacy XCTest waiting? | Replace with async XCTest or Swift Testing waiting APIs | `references/testing.md` |
| Core Data concurrency warnings | Are managed objects crossing contexts/actors? | Pass `NSManagedObjectID` or Sendable values | `references/core-data.md` |
| `Thread.current` unavailable from async context | Is code reasoning by thread instead of isolation? | Reason in terms of isolation and use tooling for thread evidence | `references/threading.md` |

## Smallest Safe Fixes

- UI-bound state: isolate the type or member to `@MainActor`.
- Shared mutable async state: move it behind an `actor`.
- Background work: use `@concurrent` async APIs when work must hop off caller isolation.
- Task entry isolation: if nothing before the first `await` needs the main actor, use `Task { @concurrent in ... }` and hop back only for UI mutation.
- Sendability: prefer immutable values and explicit transfer boundaries over `@unchecked Sendable`.

For examples and deeper patterns, open the smallest matching reference below.

## Reference Router

- `references/async-await-basics.md` — async/await syntax, closure bridges, URLSession patterns
- `references/tasks.md` — task lifecycle, cancellation, priorities, task groups
- `references/actors.md` — actor isolation, `@MainActor`, global actors, reentrancy
- `references/sendable.md` — `Sendable`, `@Sendable`, region isolation, escape hatches
- `references/threading.md` — execution model, suspension points, Swift 6.2 isolation behavior
- `references/async-sequences.md` — `AsyncSequence`, `AsyncStream`, one-shot async alternatives
- `references/async-algorithms.md` — debounce, throttle, merge, channels, timers
- `references/testing.md` — Swift Testing first, XCTest fallback, leak checks
- `references/performance.md` — Instruments workflow, actor hops, suspension cost
- `references/memory-management.md` — retain cycles, long-lived tasks, cleanup
- `references/core-data.md` — managed object sendability, `perform`, default isolation conflicts
- `references/migration.md` — Swift 6 migration strategy, callback conversion, `@preconcurrency`
- `references/linting.md` — concurrency-focused lint rules
- `references/glossary.md` — quick definitions

## Verification Checklist

When changing concurrency code:

1. Re-check build settings before interpreting diagnostics.
2. Clear one diagnostic category at a time.
3. Build before moving to the next category.
4. Run tests for actor-, lifetime-, and cancellation-sensitive code.
5. Use Instruments for performance claims.
6. Verify cancellation/deallocation for long-lived tasks.
7. Avoid semaphores or ad hoc locking in async contexts when actor isolation or `Mutex` expresses ownership more safely.

---

This skill is vendored from the Swift Concurrency course material and pinned by `Skills/External/external-skills.tsv`.
