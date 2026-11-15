# Architecture decision records

This folder holds the architecture decision records (ADRs) of Alike. An ADR
records one decision, the reason for it, and its consequences. Agents and
contributors read the ADRs before they change code style, tool configuration,
or the package graph.

## Index

| ADR | Title | Status |
|---|---|---|
| [0000](0000-template.md) | Template | Template |
| [0001](0001-alike-swift-style.md) | Alike Swift Style | Accepted |
| [0002](0002-selective-swiftlint.md) | Selective SwiftLint | Accepted |
| [0003](0003-format-change-process.md) | Format change process | Accepted |
| [0004](0004-package-dependencies.md) | Package dependencies | Accepted |
| [0005](0005-ipad-layout.md) | iPad layout: one stack, readable column, width-based grids | Proposed |

## Status values

- `Proposed`: the pull request is open. The decision is not in effect.
- `Accepted`: the decision is in effect.
- `Superseded by NNNN`: a newer ADR replaces this one. Keep the old file.
- `Rejected`: the team did not accept the proposal. Keep the file as a record.

## How to propose a change

1. Copy [0000-template.md](0000-template.md) to `NNNN-short-title.md`. Use the next free number.
2. Fill in Context, Decision, Alternatives, and Consequences.
3. Set the status to `Proposed`.
4. Add a row to the index above.
5. Open a pull request that contains the ADR, or the ADR and the change that it permits.
6. When the pull request merges, set the status to `Accepted`.

Do not edit the decision of an accepted ADR. Write a new ADR and mark the old
one `Superseded by NNNN`. You can correct typos and broken links in place.

## When you need an ADR

- A change to the SwiftFormat rules or options. See [ADR-0001](0001-alike-swift-style.md) and [ADR-0003](0003-format-change-process.md).
- A change to the SwiftLint rules or thresholds. See [ADR-0002](0002-selective-swiftlint.md).
- A new edge between packages, a new package category, or a new third-party SDK. See [ADR-0004](0004-package-dependencies.md).
