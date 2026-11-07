# 0004. Package dependencies

- Status: Accepted
- Date: 2026-11-07
- Supersedes: the generic dependency rules in `Skills/Architecture/SwiftUIModular/SKILL.md`

## Context

Alike has 2 Xcode targets that ship (`Alike`, `AlikeWidgets`) and 17 local
Swift packages under `Packages/`. The old rule was "features do not depend on
other features". It did not name the packages, the shared screens, or the SDK
rule, and no tool checked it.

## Decision

Each package has one category. The category decides which edges are
permitted. [tools/package-categories](../../tools/package-categories) is the
source of truth for the category of each package. Stage 5 adds
`tools/check-package-graph`, which reads that file and checks the edges.

### Categories

| Category | Members | Purpose |
|---|---|---|
| App | `Alike`, `AlikeWidgets` | Xcode targets. Composition root and wiring. `AlikeTests` belongs to `Alike`. |
| Feature | `Cleanup`, `Details`, `Scanner`, `Settings`, `Welcome`, `Launch` | One user flow each, with its screens and view models. |
| Foundation | `Core`, `Storage`, `PhotoAnalysis`, `NavigationKit`, `DesignSystem`, `WidgetSupport`, `Purchases`, `CleanupWorkspace` | Shared models, services, persistence, navigation, and design tokens. |
| Foundation with UI | `UserGuide`, `Diagnostics`, `PurchasesUI` (a product of `Purchases`) | Shared screens that more than one feature or the app shows. Same rules as Foundation. |
| Utility | none today | Small helper libraries with no Alike dependency. Any package can use them. |
| Tool | `BestShotCalibration` | Developer tools. Not part of the shipped app. Nothing depends on a Tool. |

"Foundation with UI" is a subgroup of Foundation, not a separate category.
Its packages must not depend on a Feature package.

### Dependency matrix

Rows are the package that depends. Columns are the dependency.

| From \ To | App | Feature | Foundation | SDK | Utility | Tool |
|---|---|---|---|---|---|---|
| App | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ |
| Feature | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ |
| Foundation | ✗ | ✗ | ✓ | Named in this ADR only | ✓ | ✗ |
| Utility | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| Tool | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ |

### SDK rule

The only third-party SDK is `lottie-spm` (`https://github.com/airbnb/lottie-spm.git`,
from `4.6.1`). Only `DesignSystem` can depend on it. `WidgetSupport` stays free
of dependencies: the widget extension has a memory limit of about 30 MB, and
Lottie does not play in WidgetKit.

A new SDK, or a new package that uses `lottie-spm`, needs a new ADR.

### BestShotCalibration

`BestShotCalibration` is a macOS-only package (`.macOS(.v14)`). It ships the
`bestshot-calibrate` command-line tool and a library with the same logic. The
tool measures the Best Shot scoring configuration of `Core` against a labelled
photo corpus. It has 3 commands: `report` (agreement and blur metrics),
`sweep` (a search for candidate weights), and `personalize` (a check that
personal weights do not make the ranking worse). No package or target imports
it.

Decision: `BestShotCalibration` is a Tool. A Tool can depend on Foundation
packages, and no package can depend on a Tool. Reasons:

- The tool must run the same scoring code that ships. A copy of the code would
  measure a different thing.
- Utility means a helper library that any package can use. A calibration
  tool is not that, so it gets its own category.
- The edge is safe: `BestShotCalibration` cannot reach the app, because it
  supports macOS only and nothing depends on it.

### The graph is a DAG

The package graph must have no cycle. SwiftPM rejects a cycle between local
packages, and `tools/check-package-graph` will report it too.

### Levels are computed

The level of a package is 0 when it has no local dependency, otherwise 1 more
than its highest dependency. `tools/check-package-graph` computes the levels
from the edges. Do not write levels in documents. A written level becomes wrong
when an edge changes.

### Changes need an ADR

A new edge between packages, a new SDK, a new package, or a category change
needs a new ADR. Update [tools/package-categories](../../tools/package-categories)
and the baseline below in the same pull request.

## Baseline: current edges

Source: `.package(path: "../X")` in each `Packages/*/Package.swift`, and the
package products of each target in `Alike/Alike.xcodeproj` on 2026-11-07
(develop `cd12c997`). All edges follow the matrix.

| Package | Category | Depends on |
|---|---|---|
| `Alike` | App | `Cleanup`, `CleanupWorkspace`, `Core`, `DesignSystem`, `Details`, `Diagnostics`, `Launch`, `PhotoAnalysis`, `Purchases` (`Purchases`, `PurchasesUI`), `Scanner`, `Settings`, `Storage`, `Welcome`, `WidgetSupport` |
| `AlikeWidgets` | App | `WidgetSupport` |
| `Cleanup` | Feature | `CleanupWorkspace`, `Core`, `DesignSystem`, `NavigationKit`, `PhotoAnalysis`, `Purchases`, `Storage` |
| `Details` | Feature | `Core`, `DesignSystem`, `NavigationKit`, `Purchases`, `Storage` |
| `Launch` | Feature | `DesignSystem` |
| `Scanner` | Feature | `CleanupWorkspace`, `Core`, `DesignSystem`, `NavigationKit`, `Purchases`, `UserGuide` |
| `Settings` | Feature | `Core`, `DesignSystem`, `Diagnostics`, `NavigationKit`, `PhotoAnalysis`, `Purchases`, `Storage`, `UserGuide` |
| `Welcome` | Feature | `Core`, `DesignSystem`, `PhotoAnalysis` |
| `CleanupWorkspace` | Foundation | `Core`, `PhotoAnalysis`, `Storage` |
| `Core` | Foundation | none |
| `DesignSystem` | Foundation | `Core`, `lottie-spm` (SDK) |
| `Diagnostics` | Foundation (UI) | `Core` |
| `NavigationKit` | Foundation | none |
| `PhotoAnalysis` | Foundation | `Core` |
| `Purchases` | Foundation; `PurchasesUI` is UI | `Core`, `DesignSystem`, `NavigationKit` |
| `Storage` | Foundation | `Core` |
| `UserGuide` | Foundation (UI) | `Core`, `DesignSystem`, `NavigationKit`, `Purchases` |
| `WidgetSupport` | Foundation | none |
| `BestShotCalibration` | Tool | `Core` |

## Alternatives

- Keep the old generic rule: it did not name packages, and no tool could check it.
- Write a level for each package: levels change with each edge, so a written
  list becomes wrong. A tool computes them.
- Make the shared screens Feature packages: then `Scanner` → `UserGuide` and
  `Settings` → `Diagnostics` would be Feature → Feature edges.

## Consequences

- A reviewer checks each `Package.swift` change against the matrix.
- Stage 5 adds `tools/check-package-graph` to the gate.
- A shared screen goes into a Foundation package. It must not import a Feature.

## Status

Accepted on 2026-11-07 by the project owner.
