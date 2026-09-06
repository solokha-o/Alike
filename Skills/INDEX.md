# Alike Skill Index

Use this index before opening any `SKILL.md`. Pick one local skill first. Pair
with an external skill only when the `External pairing` column says so and the
request needs that extra depth.

| Skill | Trigger | External pairing | Self-service possible |
|---|---|---|---|
| `Architecture/adaptive-ui-layout` | Responsive SwiftUI layout, iPhone/iPad adaptation, size classes, Dynamic Type | Rarely; use SwiftUI external only for platform API uncertainty | No |
| `Architecture/change-safety` | Changing shipped code: public package APIs, persisted values, enum cases, user-visible flows; extension-vs-modification decisions, breaking-change gating | Rarely; pair with `Storage/persisted-data-evolution` when the change touches stored data | No |
| `Architecture/SwiftUIModular` | New package/module, package boundaries, modular SwiftUI architecture | Rarely; use SwiftUI external only for broad platform API guidance | No |
| `DesignConcept` | Native SwiftUI design concepts, colors, typography, SF Symbols | Rarely; use SwiftUI external only for API-specific design implementation | No |
| `DesignConcept/app-store-screenshots` | App Store screenshots, product/marketing screenshots, screenshot copy, phone mockups, screenshot generator | No | No |
| `External/core-data-expert` | Core Data, migrations, persistent history, fetch/context issues | This is already external depth; use directly only for Core Data tasks | No |
| `External/xcode-build-optimization` | Vendored AvdLee build-optimization pack: benchmarking, compilation, project settings, SPM graph, applying fixes | Enter through local `Performance/xcode-build-performance`; load exactly one sub-skill | Yes (`benchmark`) |
| `External/emilkowalski-skills/animation-vocabulary` | Name or disambiguate an animation/motion effect from a visual description | This is external terminology depth; use directly for naming, not implementation | Yes |
| `External/emilkowalski-skills/apple-design` | Apple-style fluid motion, gesture physics, interruptibility, feedback, and spatial consistency | Pair with the narrowest local SwiftUI/design skill; translate web examples to native SwiftUI and keep local guidance authoritative | No |
| `External/emilkowalski-skills/emil-design-eng` | UI polish, component design judgment, animation decisions, and interaction details | Pair with `DesignConcept` or the narrowest local SwiftUI skill; adapt web-specific recipes to native APIs | No |
| `External/emilkowalski-skills/find-animation-opportunities` | Read-only search for UI moments that would genuinely benefit from motion | Pair with the relevant local SwiftUI skill; proposals only, with SwiftUI-native values and accessibility handling | No |
| `External/emilkowalski-skills/improve-animations` | Read-only animation audit with self-contained plans returned in the response; never create plan files | Pair with local `swiftui-performance-audit` or `swiftui-ui-patterns`; local read-only routing overrides upstream plan-file writes, and web-specific rules never override native platform behavior | No |
| `External/emilkowalski-skills/review-animations` | Explicit review of animation or motion code against a strict craft bar | Pair with local `swiftui-code-review`; respect its `disable-model-invocation` metadata and use only when explicitly requested | No |
| `External/swift-concurrency` | Deep Swift concurrency migration or Sendable/isolation diagnostics beyond the local skill | This is external depth; do not use for routine async fixes | No |
| `External/swift-testing-expert` | Swift Testing API depth, traits/tags, parameterization, XCTest modernization | This is external depth; pair with local testing only when needed | No |
| `External/swiftui-expert-skill` | Broad/current SwiftUI APIs, Instruments trace recording/analysis, platform guidance | This is external depth; do not use for routine local SwiftUI refactors | No |
| `Performance/app-runtime-performance` | App is slow at scale: launch, scan/analysis throughput, memory, thermals, Core Data query cost | Pair with `External/core-data-expert` for deep fetch diagnostics | No |
| `Performance/xcode-build-performance` | Build or compile time, benchmarking builds, slow type-checking, project/package build settings | Pair with `External/xcode-build-optimization` for the analysis depth | No |
| `GitFlow/ios-git-flow` | Branching, commits, version/build numbers, release tags, develop/main merge | No | No |
| `GitFlow/pr-agent-flow` | Pull request preparation, self-review, PR descriptions, and review-comment response with separate coding/review passes | No | No |
| `Localization/spm-localization` | `.xcstrings`, package localization, typed wrappers, the twelve shipped locales, CLDR plurals | Pair with Core Data external only when localized model labels cross persistence boundaries | No |
| `Meta/skill-authoring-governance` | Create, slim, decompose, or update skills | Pair with `project-skill-audit` for audits | No |
| `project-skill-audit` | Audit project-local skills, suggest updates/new skills, reduce skill duplication | Pair with `Meta/skill-authoring-governance` for implementation | No |
| `Storage/persisted-data-evolution` | Core Data model edits, `UserDefaults` keys, `Codable`/`Data` payload changes, migration safety for users with existing data | Pair with `External/core-data-expert` only for mapping models or heavyweight migration depth | No |
| `SwiftConcurrency/app-store-changelog` | App Store “What’s New”, release notes from git history/tags | No | No |
| `SwiftConcurrency/gh-issue-fix-flow` | Fix a GitHub issue end-to-end with `gh`, validation, commit, push | Pair with GitHub plugin/CLI only when issue access is needed | No |
| `SwiftConcurrency/ios-debugger-agent` | Build/run/debug on iOS Simulator, inspect UI/logs/runtime state, or add debug-only app access such as premium overrides and feature flags | Pair with Build iOS tools when available | No |
| `SwiftConcurrency/macos-spm-app-packaging` | SwiftPM macOS app scaffold/build/package/sign/notarize | Pair with Build macOS tools only for packaging/signing depth | No |
| `SwiftConcurrency/swift-concurrency-expert` | Local Swift concurrency review/fixes, actors, `@MainActor`, Sendable | Use external concurrency only for deeper migration/diagnostic depth | No |
| `SwiftConcurrency/swiftui-liquid-glass` | iOS 26+ SwiftUI Liquid Glass implementation/review | Pair with SwiftUI external only for latest API uncertainty | No |
| `SwiftUI/swiftui-code-review` | SwiftUI view audit, lifecycle/rendering/update-minimization review | Use external SwiftUI only for broad API/deprecation questions | No |
| `SwiftUI/swiftui-magic-numbers` | Extract hardcoded SwiftUI layout/typography/animation values | No | No |
| `SwiftUI/swiftui-performance-audit` | SwiftUI performance, slow UI, profiling-backed optimization | Use external SwiftUI only for Instruments trace analysis | No |
| `SwiftUI/swiftui-ui-patterns` | Create/refactor SwiftUI UI, TabView, sheets, navigation, reusable components, static hero + Lottie overlays | Use external SwiftUI only for broad/current API guidance | No |
| `SwiftUI/swiftui-view-refactor` | Split/refactor SwiftUI views, structure/order, MV/Observation patterns | Use external SwiftUI only for API uncertainty | No |
| `Testing/swift-testing` | Add/fix/review tests, async test isolation, package test architecture, XCTest migration planning | Use external testing only for API depth or large-scale migration details | No |
| `Workflow/sqim-phone-setup` | Explicit request to set up, install, or push Alike on the user's physical phone/iPhone with SQIM; never ordinary build or simulator work | No | No |
| `Workflow/todo-management` | Create, review, audit, resolve, or report TODO-family comments and deferred code work | No | No |
| `Workflow/workspace-hygiene` | Keep temporary files, build artifacts, logs, screenshots, exports, and other disposable workspace clutter out of the repository | No | No |

## Routine Commands

The user can run these directly when no interpretation is needed:

- `find Skills -name SKILL.md | sort`
- `./Skills/External/check-updates.sh`

Agents should handle failures, scope decisions, repo mutations, skill edits,
release/version flows, and any repo-specific validation planning.
