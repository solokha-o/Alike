---
name: xcode-build-performance
description: Measure and improve Alike build times (clean and incremental) using the vendored Xcode build-optimization pack, with this repo's toolchain, scheme, and artifact-hygiene rules pinned.
---

# Xcode Build Performance (Alike)

Use this skill when build or compile **time** is the problem: slow clean builds,
slow incremental builds, long `CompileSwiftSources`, package resolution cost, or
"did my change make builds slower".

For app **runtime** performance use `Skills/Performance/app-runtime-performance/SKILL.md`.
For SwiftUI rendering specifically use `Skills/SwiftUI/swiftui-performance-audit/SKILL.md`.

## Routing

This is a thin local wrapper. The analysis depth lives in the vendored pack
`Skills/External/xcode-build-optimization/` (AvdLee, pinned in
`Skills/External/external-skills.tsv`; the same pack is installed globally in
`~/.claude/skills`, so either copy may be loaded — the local pin is the one this
repo is validated against).

| Request | Entry point |
|---|---|
| Full end-to-end optimization pass | `xcode-build-orchestrator/SKILL.md` |
| Just a baseline / before-after numbers | `xcode-build-benchmark/SKILL.md` |
| Slow Swift type-checking, compile hotspots | `xcode-compilation-analyzer/SKILL.md` |
| Build settings, schemes, script phases | `xcode-project-analyzer/SKILL.md` |
| Package graph, plugins, resolution cost | `spm-build-analysis/SKILL.md` |
| Applying an approved plan | `xcode-build-fixer/SKILL.md` |

Load exactly one entry point. Do not bulk-read the pack.

## Repo Bindings (override the vendored defaults)

- Toolchain: bare `xcodebuild` fails on this machine because `xcode-select`
  points at the Command Line Tools. Prefix ad-hoc commands with
  `DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer`, or use the
  repo's `tools/xcode-env.sh`. Never benchmark with a beta Xcode.
- Project/scheme: `-project Alike/Alike.xcodeproj -scheme Alike`.
- Destination: the ID pinned in `AGENTS.md` may not exist on a given machine;
  pick an available simulator and **keep the same destination for every run in
  one comparison**.
- `swift build` / `swift test` under `Packages/` is not a valid benchmark here
  (`#Preview` needs a plugin that only ships with full Xcode); benchmark through
  `xcodebuild`.
- Artifacts (`.build-benchmark/`, timing summaries, logs) are disposable: they
  stay gitignored and out of commits — `Skills/Workflow/workspace-hygiene/SKILL.md`.

## Strict Rules

- **No number, no claim.** Every "this is faster" needs a before and an after
  from the same script, same machine, same destination, same Xcode, with other
  builds idle. Report the median, not the best run.
- **Measure first, change second.** Do not apply build-setting changes before a
  baseline exists.
- **Recommend before mutating.** Build settings, script phases and package
  restructuring are approved by the user itemised, then applied — that is the
  vendored pack's own contract, and it holds here.
- **One lever per commit.** A build-settings change and a source refactor in one
  commit make the measurement meaningless.
- A build-time change that alters what ships (optimisation level, stripping,
  `SWIFT_COMPILATION_MODE` for Release, dead-code stripping) is a runtime and
  correctness change too: re-run the app, and treat it under
  `Skills/Architecture/change-safety/SKILL.md`.
- Never trade Release safety for build speed: debug-only settings stay in the
  Debug configuration.

## Related Skills

- `Skills/Performance/app-runtime-performance/SKILL.md`
- `Skills/Architecture/SwiftUIModular/references/xcode-schemes-configurations.md`
- `Skills/Workflow/workspace-hygiene/SKILL.md`
