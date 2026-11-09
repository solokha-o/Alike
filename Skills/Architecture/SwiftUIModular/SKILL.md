---
name: swiftui-modular-architecture
description: Modular SwiftUI architecture with Swift Packages by domain, MVVM, small composable views, and a thin app target.
---

# Modular SwiftUI Architecture (iOS)

Use this skill when the user wants a modular SwiftUI iOS architecture with Swift Packages and MVVM.

## Core principles

- Split the app into **Swift Packages by domain/feature** to keep the codebase organized and maintainable.
- Use **straightforward MVVM** (no Redux) for most parts.
- Keep the app target focused on wiring and composition; push feature code into packages.
- Each package should focus on a specific aspect (UI, networking, data models, etc.).
- Prefer clear dependency boundaries so features can be developed, tested, and replaced independently.
- Treat "different responsibility" as the main signal for a new package, not file size alone.

## Alike packages and categories

The source of truth is `Docs/adr/0004-package-dependencies.md` (ADR-0004) and
`tools/package-categories`. Summary:

| Category | Members |
|---|---|
| App | `Alike` (composition root, with `AlikeTests`), `AlikeWidgets` |
| Feature | `Cleanup`, `Details`, `Launch`, `Scanner`, `Settings`, `Welcome` |
| Foundation | `CleanupWorkspace`, `Core`, `DesignSystem`, `NavigationKit`, `PhotoAnalysis`, `Purchases`, `Storage`, `WidgetSupport` |
| Foundation with UI | `Diagnostics`, `UserGuide`, `PurchasesUI` (product of `Purchases`) |
| Utility | none today (helper libraries any package can use) |
| Tool | `BestShotCalibration` (macOS calibration tool, not shipped; nothing depends on it) |

Permitted edges (row depends on column):

| From \ To | Feature | Foundation | SDK | Utility | Tool |
|---|---|---|---|---|---|
| App | ✓ | ✓ | ✓ | ✓ | ✗ |
| Feature | ✗ | ✓ | ✗ | ✓ | ✗ |
| Foundation | ✗ | ✓ | Named in ADR-0004 only | ✓ | ✗ |
| Utility | ✗ | ✗ | ✗ | ✓ | ✗ |
| Tool | ✗ | ✓ | ✗ | ✓ | ✗ |

- No package depends on an App target.
- The only SDK is `lottie-spm`, and only `DesignSystem` uses it.
- A Tool (`BestShotCalibration`) can depend on Foundation; nothing depends on a Tool.
- The graph is a DAG. Levels are computed by `tools/check-package-graph`, not written.
- A new edge, a new SDK, a new package, or a category change needs a new ADR.

Run `tools/check-package-graph` after each change to a `Package.swift`, a
category, or a local `import`. It checks the matrix, the SDK rule, cycles, and
that each package imports only the local modules it declares. It also prints
the level of each module. `tools/quick` and `tools/full` run it. If it reports
a new edge, write an ADR first. Then update `tools/package-categories` or add
the exception with its reason to `tools/package-graph.allowlist`.

Composition root: the `Alike` app target creates the concrete services and
passes them to the view models of the Feature packages.

## View model pattern (team convention)

- One main view + one view model per screen/flow.
- The view model is a `@MainActor @Observable final class`. The main view owns it via `@State`, made in `init`.
- Give subviews narrow inputs (values and closures). Use `@Bindable` only when a subview needs bindings to the view model.
- Compose the UI from small, targeted subviews.

## Dependency injection

- Depend on protocols in features; provide concrete implementations in the `Alike` app target (the composition root).
- Use constructor injection for view models and services; avoid global singletons.
- Provide test doubles in each package’s test target.

## When to create a new package

Create or recommend a new package when:

- The code serves a separate domain or infrastructure responsibility.
- The package would clarify dependency direction and reduce cross-feature leakage.
- The extracted code can own its own protocols, tests, and implementation without leaning on feature UI types.
- More than one feature is likely to depend on the code, or the code is clearly broader than the current feature.

Do not create a new package when:

- The boundary is speculative and the code is still feature-specific.
- A dedicated file or service inside the current package solves the issue cleanly.
- The extracted package would become a vague grab bag instead of a coherent module.

## How to add a new feature

1) Write an ADR for the new package and its edges (ADR-0004), and add it to `tools/package-categories`.
2) Create `Packages/<Feature>` from `references/templates/Package.swift` (its header lists the README and Xcode project steps).
3) Add feature views + view models + service protocols.
4) Wire it in the app target (routing/navigation).
5) Add tests inside the package.

## Guardrails

- Keep cross‑package dependencies minimal.
- Avoid putting heavy logic in the app target.
- Prefer shared UI helpers in a dedicated shared package rather than cross‑importing features.
- Features may depend on shared/core packages, but not on other features.
- Keep navigation/routing in the app target or a dedicated routing package.
- Avoid static global state unless it is explicitly isolated (actor or MainActor).
- Once a symbol is `public` and shipped, prefer extending it over changing it; for
  any change to a shipped `public` API or to persisted data, follow
  `Skills/Architecture/change-safety/SKILL.md`.

## Dependency rules

- Follow the matrix above and ADR-0004.
- A screen that more than one feature shows goes into a Foundation package
  (example: `UserGuide`, `Diagnostics`), never into a Feature package.

## Navigation

- Keep navigation state centralized at the feature or app composition root.
- In this repo, prefer `NavigationKit` and `RoutedNavigationStack` for project-owned navigation rather than new raw `NavigationStack` wrappers.
- If navigation grows complex beyond the current package, extract or expand a dedicated routing package instead of recreating ad hoc routers across features.

## Testing

- Unit tests live inside each package.
- UI tests live in the app target.
- Prefer testable view models and repositories with protocol-based dependencies.
- Add integration tests for data flows that span multiple packages where practical.

## References

| Need | Reference |
|---|---|
| Style: what SwiftFormat and SwiftLint enforce, the 15 written rules (ADR-0001 to ADR-0003) | `references/swift-code-style.md` |
| File layout, when and how to split, one way per task (DI, errors, logging, navigation), known debt. A new way needs an ADR. | `references/file-structure.md` |
| Templates: `View`, `ViewModel`, `Service`, `FeatureTests`, `Package` | `references/templates/` |
| SwiftUI view rules, state wrapper table, 6-item review checklist | `references/swiftui-view-rules.md`, `references/view-review-checklist.md` |
| Data layer, caching, error resiliency, observability | `references/data-layer.md` |
| `///` and `//` comments, markers. Comments are in English; translate a non-English comment in a file that you change. | `references/code-documentation.md` |
| README of a new package (category from ADR-0004) | `references/package-readme-template.md` |
| Schemes, build configurations, `#if DEBUG`, feature flags | `references/xcode-schemes-configurations.md` |

`tools/quick` and `tools/full` run `ALIKE_LINT_STRICT=1 tools/lint` on the
changed Swift files before the package tests. Install the pre-commit hook once
with `tools/install-hooks`. If a commit stops, run `tools/lint --fix`, then
`git add` the files.
