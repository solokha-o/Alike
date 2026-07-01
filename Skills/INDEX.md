# Alike Skill Index

Use this index before opening any `SKILL.md`. Pick one local skill first. Pair
with an external skill only when the `External pairing` column says so and the
request needs that extra depth.

| Skill | Trigger | External pairing | Self-service possible |
|---|---|---|---|
| `Architecture/adaptive-ui-layout` | Responsive SwiftUI layout, iPhone/iPad adaptation, size classes, Dynamic Type | Rarely; use SwiftUI external only for platform API uncertainty | No |
| `Architecture/SwiftUIModular` | New package/module, package boundaries, modular SwiftUI architecture | Rarely; use SwiftUI external only for broad platform API guidance | No |
| `DesignConcept` | Native SwiftUI design concepts, colors, typography, SF Symbols | Rarely; use SwiftUI external only for API-specific design implementation | No |
| `External/core-data-expert` | Core Data, migrations, persistent history, fetch/context issues | This is already external depth; use directly only for Core Data tasks | No |
| `External/swift-concurrency` | Deep Swift concurrency migration or Sendable/isolation diagnostics beyond the local skill | This is external depth; do not use for routine async fixes | No |
| `External/swift-testing-expert` | Swift Testing API depth, traits/tags, parameterization, XCTest modernization | This is external depth; pair with local testing only when needed | No |
| `External/swiftui-expert-skill` | Broad/current SwiftUI APIs, Instruments trace recording/analysis, platform guidance | This is external depth; do not use for routine local SwiftUI refactors | No |
| `GitFlow/ios-git-flow` | Branching, commits, version/build numbers, release tags, develop/main merge | No | No |
| `Localization/spm-localization` | `.xcstrings`, package localization, typed wrappers, EN/UK strings, pluralization | Pair with Core Data external only when localized model labels cross persistence boundaries | No |
| `Meta/skill-authoring-governance` | Create, slim, decompose, or update skills | Pair with `project-skill-audit` for audits | No |
| `project-skill-audit` | Audit project-local skills, suggest updates/new skills, reduce skill duplication | Pair with `Meta/skill-authoring-governance` for implementation | No |
| `SwiftConcurrency/app-store-changelog` | App Store “What’s New”, release notes from git history/tags | No | No |
| `SwiftConcurrency/gh-issue-fix-flow` | Fix a GitHub issue end-to-end with `gh`, validation, commit, push | Pair with GitHub plugin/CLI only when issue access is needed | No |
| `SwiftConcurrency/ios-debugger-agent` | Build/run/debug on iOS Simulator, inspect UI/logs/runtime state | Pair with Build iOS tools when available | No |
| `SwiftConcurrency/macos-spm-app-packaging` | SwiftPM macOS app scaffold/build/package/sign/notarize | Pair with Build macOS tools only for packaging/signing depth | No |
| `SwiftConcurrency/swift-concurrency-expert` | Local Swift concurrency review/fixes, actors, `@MainActor`, Sendable | Use external concurrency only for deeper migration/diagnostic depth | No |
| `SwiftConcurrency/swiftui-liquid-glass` | iOS 26+ SwiftUI Liquid Glass implementation/review | Pair with SwiftUI external only for latest API uncertainty | No |
| `SwiftUI/swiftui-code-review` | SwiftUI view audit, lifecycle/rendering/update-minimization review | Use external SwiftUI only for broad API/deprecation questions | No |
| `SwiftUI/swiftui-magic-numbers` | Extract hardcoded SwiftUI layout/typography/animation values | No | No |
| `SwiftUI/swiftui-performance-audit` | SwiftUI performance, slow UI, profiling-backed optimization | Use external SwiftUI only for Instruments trace analysis | No |
| `SwiftUI/swiftui-ui-patterns` | Create/refactor SwiftUI UI, TabView, sheets, navigation, reusable components | Use external SwiftUI only for broad/current API guidance | No |
| `SwiftUI/swiftui-view-refactor` | Split/refactor SwiftUI views, structure/order, MV/Observation patterns | Use external SwiftUI only for API uncertainty | No |
| `Testing/swift-testing` | Add/fix/review tests, async test isolation, package test architecture, XCTest migration planning | Use external testing only for API depth or large-scale migration details | No |

## Routine Commands

The user can run these directly when no interpretation is needed:

- `find Skills -name SKILL.md | sort`
- `./Skills/External/check-updates.sh`

Agents should handle failures, scope decisions, repo mutations, skill edits,
release/version flows, and any repo-specific validation planning.
