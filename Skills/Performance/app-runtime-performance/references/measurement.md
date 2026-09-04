# Measurement

## Pick the metric before touching code

State it in the form: *"<phase> on <device>, <library size>: <number> <unit>"*.

Useful metrics for Alike:

| Phase | Metric |
|---|---|
| Cold launch | time to first interactive frame |
| Scan | photos analysed per second, and total wall clock for a fixed library |
| Analysis step | median and p95 milliseconds per photo |
| Memory | peak footprint during a scan, not the idle value |
| Storage | duration of the slowest fetch and the number of rows it faulted |
| Battery / thermals | thermal state reached during a full scan |

Averages hide the problem. Report median **and** p95; a scan is judged by its
worst batches.

## Signposts

The repo already logs through `Packages/Core/Sources/Core/Logging/AppLog.swift`.
For timing, prefer `OSSignposter` intervals around a phase over `print` or
ad-hoc `Date()` differences: signposts show up in Instruments, cost almost
nothing in Release, and do not need removing afterwards.

- One signpost per *phase* (fetch, decode, feature print, cluster, persist), not
  per photo, unless you are actively chasing per-item variance.
- Never log photo identifiers, file paths or user content into signpost
  metadata; counts and durations only.
- Do not leave `print` in production paths — that is a project-wide rule.

## Instruments

- Always profile a **Release** build; Debug numbers are noise.
- Profile on a real device with a real library. The simulator has different
  memory, disk and Vision behaviour, and will not reproduce thermal throttling.
- Templates: **Time Profiler** for CPU, **Allocations** / **Leaks** for memory
  growth, **os_signpost** for phase timing, **SwiftUI** only when the view layer
  is suspected.
- Record the same interaction on both sides of the change, same device, same
  library, same thermal starting point (let the device cool down between runs).

## Reporting

A performance claim in a PR body must include:

- device + iOS version, library size, build configuration;
- before and after, median and p95;
- what got faster and **what got slower** (there is almost always a trade);
- the guard that prevents the regression returning.

"Feels faster" is not a result.

## Regression guards

- A test with a representative N that asserts the algorithm's shape (batch
  count, number of fetches, number of image requests) rather than wall-clock
  time — timing assertions are flaky in CI.
- Or a logged duration with a threshold that surfaces in debug builds.

Keep benchmark scratch files, traces and exports out of the repository
(`Skills/Workflow/workspace-hygiene/SKILL.md`).
