# External Skills

This folder stores vendored third-party skills used together with Alike local
skills.

## Routing Rules

- Prefer local Alike skills for project-specific paths, package boundaries,
  validation commands, and commit conventions.
- Pair an external skill with a local skill only when the request needs the exact deeper coverage listed below.
- Do not load vendored external skills for ordinary local implementation, review, or test tasks.
- Do not treat external skills as replacements for local skills unless the local skill is missing that topic.
- If local and external guidance conflicts, follow the local Alike skill and
  mention the conflict when it affects the result.
- For `improve-animations`, return plans in the response and never create or
  edit `plans/` or `animation-plans/`; this local read-only rule overrides the
  vendored skill's plan-file instructions.

## Vendored Skills

- `swiftui-expert-skill` from `solokha-o/SwiftUI-Agent-Skill`
- `swift-concurrency` from `AvdLee/Swift-Concurrency-Agent-Skill`
- `core-data-expert` from `AvdLee/Core-Data-Agent-Skill`
- `swift-testing-expert` from `AvdLee/Swift-Testing-Agent-Skill`
- `xcode-build-optimization` from `AvdLee/Xcode-Build-Optimization-Agent-Skill`, containing:
  - `xcode-build-orchestrator`
  - `xcode-build-benchmark`
  - `xcode-compilation-analyzer`
  - `xcode-project-analyzer`
  - `spm-build-analysis`
  - `xcode-build-fixer`
- `emilkowalski-skills` from `emilkowalski/skills`, containing:
  - `animation-vocabulary`
  - `apple-design`
  - `emil-design-eng`
  - `find-animation-opportunities`
  - `improve-animations`
  - `review-animations`

## Duplication Map

- `swiftui-expert-skill` overlaps with local `Skills/SwiftUI/*`.
  Default to local SwiftUI skills. Use this external skill only for broad/current SwiftUI API coverage, Instruments trace recording/analysis, or platform guidance not covered locally.
- `swift-concurrency` overlaps with local `Skills/SwiftConcurrency/swift-concurrency-expert`.
  Default to the local concurrency skill. Use this external skill only for deep Sendable/isolation diagnostics, Swift 6 migration details, or diagnostics beyond the local router.
- `swift-testing-expert` overlaps with local `Skills/Testing/swift-testing`.
  Default to the local testing skill. Use this external skill only for Swift Testing API depth, traits/tags, parameterized testing, async waiting, or XCTest modernization.
- `xcode-build-optimization` has no local equivalent for build-time analysis, but
  it must be entered through local `Skills/Performance/xcode-build-performance/SKILL.md`,
  which pins this repo's toolchain (`DEVELOPER_DIR`), scheme, destination and
  artifact-hygiene rules and overrides the pack's generic defaults. The same pack
  is also installed globally in `~/.claude/skills`; the vendored, pinned copy is
  the one this repo is validated against. Load exactly one sub-skill per task.
- `core-data-expert` has no local Core Data equivalent.
  Use it when Core Data, migrations, persistent history, CloudKit sync, fetches, or context/threading issues are involved.
- `emilkowalski-skills` overlaps with local `Skills/DesignConcept` and
  `Skills/SwiftUI/*` skills. Use the pack for motion vocabulary, design-engineering
  judgment, animation opportunities, and focused animation audits. Its examples
  and some hard rules target web technologies; translate them to native SwiftUI,
  use Apple accessibility APIs, and keep local Alike guidance authoritative.
  Respect each vendored skill's mutation limits and invocation metadata.

## Update Policy

External skills are pinned in `external-skills.tsv`.

Run `./Skills/External/check-updates.sh` only when:

- the user asks to add, update, audit, or compare skills;
- changing `AGENTS.md` or files under `Skills/` that affect skill routing;
- the last external-skill check is older than 30 days and the current task is skill-maintenance related.

Do not run update checks for ordinary implementation, bug fix, review, or test tasks. This avoids frequent network calls and unnecessary token spend.
