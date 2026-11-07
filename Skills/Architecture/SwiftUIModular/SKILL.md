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
- The graph is a DAG. Levels are computed by `tools/check-package-graph` (stage 5), not written.
- A new edge, a new SDK, a new package, or a category change needs a new ADR.

Composition root: the `Alike` app target creates the concrete services and
passes them to the view models of the Feature packages.

## View model pattern (team convention)

- One main view + one view model per screen/flow.
- The main view owns the view model via `@StateObject` (or `@State` for `@Observable` types).
- Pass the view model to subviews via `@ObservedObject`/`@Bindable` or plain `let`.
- Compose the UI from small, targeted subviews.

## Data layer & dependencies

- Use a `Repository` or `Client` protocol per domain to isolate data access.
- Alike has no networking package. Persistence lives in `Storage`; photo analysis lives in `PhotoAnalysis`.
- Cache policies (memory/disk) live behind repositories; keep UI unaware of cache details.
- Use DTOs at the network boundary and map to domain models in the data layer.
- Prefer immutable domain models; store mutability in caches/repositories.

## Offline-first & caching guidelines

- Treat cache as the primary read source; network is for refresh.
- Flow: `load cache → show UI → refresh in background → update cache → UI updates`.
- Expose cache age or freshness so UI can show "last updated".
- Use write-through: on successful network fetch, update cache immediately.
- Support a manual refresh path even when cache is available.
- Choose cache policy per feature (stale-while-revalidate, time-based expiry, or size-based eviction).
- If offline, return cached data with an explicit "stale" marker; avoid empty screens.

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
2) Create a new Swift Package under `Packages/<Feature>`.
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

## Error handling & resiliency

- Model domain errors explicitly; avoid pinpointing UI to raw network errors.
- Handle transient failures with retry/backoff at the data layer.
- Provide user-friendly error states at the view level (empty, loading, error).

## Observability (non-CI)

- Add lightweight logging in data/repository layers for request/response failures.
- Use analytics/telemetry behind a protocol so it can be mocked in tests.

## Code style and documentation

### Style guide

Follow Alike Swift Style. See `references/swift-code-style.md` for:
- What SwiftFormat and SwiftLint enforce (ADR-0001, ADR-0002)
- How to change a format rule (ADR-0003)
- The 15 written rules that reviewers check

### Documentation

Follow structured documentation standards for public APIs and inline comments. See `references/code-documentation.md` for:
- When and how to use `///` doc comments with markup
- Inline comment (`//`) best practices
- Special markers (`TODO`, `FIXME`, `WARNING`)
- Complete examples for classes, protocols, and functions
- Use English only for code documentation and comments (`///`, `//`, `// MARK:`).
- If existing comments are non-English, convert them to English when touching the file.

### Build configurations and schemes

Organize Xcode schemes and build configurations for multiple deployment targets. See `references/xcode-schemes-configurations.md` for:
- Setting up Debug/Staging/Release configurations
- Creating schemes per environment (Production, Staging, Testing)
- Conditional compilation (`#if DEBUG`, `#if STAGING`)
- Testing with test data (launch arguments, environment variables, mock injection)
- Bundle identifier strategies for side-by-side installs
- CI/CD integration (GitHub Actions, Fastlane)
- Debug menu and feature flags patterns
