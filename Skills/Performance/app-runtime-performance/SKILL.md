---
name: app-runtime-performance
description: Keep Alike fast and predictable at real photo-library scale — launch, scan and analysis throughput, memory and thermals, Core Data query cost — with measurement-first rules and no regressions for users who already have data.
---

# App Runtime Performance (Alike)

Use this skill when the app itself is slow, heavy, or unpredictable: long
launch, a scan that crawls or gets killed, memory growth, thermal throttling,
battery drain, or a screen that stalls on large libraries.

Scope split:

| Symptom | Skill |
|---|---|
| Rendering, scrolling, view updates | `Skills/SwiftUI/swiftui-performance-audit/SKILL.md` |
| Build/compile time | `Skills/Performance/xcode-build-performance/SKILL.md` |
| Everything else at runtime (pipeline, storage, memory, launch) | this skill |

The user base is real and their libraries are large. A change that is fast on a
300-photo simulator library and quadratic on 40 000 photos is a regression for
exactly the users who matter most.

## Strict Rules

1. **Measure before and after, on a large library.** No optimisation lands on a
   hunch. State the metric, the device, the library size, and both numbers.
2. **Never regress at scale to win at small N.** Report complexity, not just
   wall clock: an O(n²) comparison pass that got a 2× constant-factor win is
   still a regression waiting for a bigger library.
3. **Bounded concurrency only.** Image and Vision work goes through the shared
   pool (`ImageAnalysisTaskPool`), never an unbounded `TaskGroup` and never a
   `for await` that materialises every asset first.
4. **Nothing unbounded in memory.** No "load all photos into an array" step: page
   fetches, stream results, and let each batch drain before the next.
5. **Every long operation is cancellable and resumable.** `Task.checkCancellation()`
   inside loops; partial progress is persisted so a killed or backgrounded scan
   does not restart from zero.
6. **One bad item never fails the batch.** Per-item failures are logged and
   skipped, as the pool already does.
7. **No blocking work on the main actor.** Fetching, decoding, hashing, Vision,
   file I/O and Core Data queries run off the main actor; only the results
   cross back.
8. **Recompute lazily, never mass-invalidate.** When a scoring or thumbnail
   input changes, bump the version marker and re-measure on access
   (`scoringModelVersion`, `thumbnailConfigVersion`) — do not sweep the whole
   store on launch. See `Skills/Storage/persisted-data-evolution/SKILL.md`.
9. **Respect the device, not just the clock.** Back off on thermal pressure and
   Low Power Mode, and keep background work inside its budget rather than
   racing until the system kills the app.
10. **A performance fix is still a change.** If it alters stored data, defaults,
    or a public API, it goes through `Skills/Architecture/change-safety/SKILL.md`.

## Workflow

1. Reproduce with a realistic library and write down the symptom in numbers.
2. Instrument: signposts around the suspect phase, then Instruments
   (Time Profiler / Allocations / os_signpost). See `references/measurement.md`.
3. Locate the dominant cost — usually one of: per-asset image requests, Vision
   feature prints, Core Data fetch/faulting, or main-actor hops.
4. Fix the dominant cost only; re-measure before touching anything else.
5. Add a guard so the regression cannot come back silently (a test with a
   representative N, or a logged duration with a threshold).
6. Report before/after with the same setup on both sides.

## Reference Map

| File | Use when |
|---|---|
| `references/measurement.md` | Choosing the metric, adding signposts, running Instruments, reporting results |
| `references/scan-pipeline.md` | PhotoKit fetches, image loading, Vision, concurrency, memory, thermals, cancellation |
| `references/coredata-query-performance.md` | Slow fetches, faulting, batching, large writes, main-thread contention |

## Related Skills

- `Skills/SwiftUI/swiftui-performance-audit/SKILL.md` — view-layer cost
- `Skills/Storage/persisted-data-evolution/SKILL.md` — when the fix touches stored data
- `Skills/SwiftConcurrency/swift-concurrency-expert/SKILL.md` — isolation and actor hops
- `Skills/External/core-data-expert/SKILL.md` — deeper Core Data diagnostics
