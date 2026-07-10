# Responsibility Boundaries Review Reference

Use this reference when a review request is really about duplicated logic, service extraction,
or file ownership drift rather than purely SwiftUI rendering issues.

## What to Flag

- The same async workflow appears in 2 or more view models or screens.
- The same domain error-to-UI-message switch appears in multiple places.
- The same repository save/delete/load sequence appears in multiple features.
- A single file mixes a screen, a reusable helper type, and domain/service logic.
- A view or view model owns persistence/networking/cleanup logic that another screen already owns too.
- A feature package now contains code that serves a broader or clearly different responsibility than that feature.

## Extraction Heuristics

Extract a shared service or coordinator when:

- The logic is reused in 2 or more places.
- The workflow has multiple steps with failure handling.
- The logic touches repositories, clients, storage, cleanup, or domain mapping.
- The workflow needs independent unit tests.

Keep the logic local when:

- It is view-only formatting or layout glue.
- It is a tiny one-off transform with no side effects.
- Extracting it would create a name with no stable responsibility.

## Choosing the Right Extraction

Prefer a `Service` when:

- It performs reusable domain work.
- It talks to repositories, clients, or other services.
- It has a clear verb-based responsibility such as delete, refresh, resurface, or summarize.

Prefer a `Coordinator` when:

- The logic orchestrates several steps across dependencies.
- It prepares a result that the view model turns into UI state.
- The value is mainly in sequencing rather than owning domain data.

Prefer a plain helper or extension when:

- The logic is pure, synchronous, and narrowly scoped.
- It does not justify state, injection, or dedicated tests.

## File Boundary Rules

- One file should have one primary reason to change.
- Keep `View` and `ViewModel` in separate files when both exist.
- Move feature support types into their own files when they are reused or materially distract from the main file.
- Do not hide service logic at the bottom of a view model file just because Swift allows multiple types per file.
- Keep package placement aligned with dependency direction:
  - feature package for feature-only services
  - shared package only when multiple features genuinely depend on it

## Package Extraction Signals

Consider recommending a new package when:

- The code has a different reason to change than the surrounding feature.
- Multiple features would depend on it, even if only one feature uses it today.
- The code owns infrastructure concerns such as storage, navigation, networking, or analysis rather than screen-specific behavior.
- The dependency direction is awkward because feature code is starting to feel like shared platform code.
- Tests for the code would make more sense as a standalone package test target.

Keep the code in the current package when:

- It is tightly coupled to one feature's screen flow or domain language.
- The reuse is speculative rather than real.
- Splitting it would create a package with only thin wrappers and no stable boundary.

## Review Output Language For Package Moves

When package extraction is justified, report it explicitly:

- "This service has infrastructure responsibility and should move from the feature package into a new shared package."
- "These types are no longer screen-specific; extract them into a dedicated package with a clearer dependency boundary."
- "The current package mixes UI and storage concerns; split storage logic into its own package."

## Review Output Language

When reporting findings, use concrete wording:

- "Duplicate delete workflow across two view models; extract a shared cleanup coordinator."
- "This file mixes screen state and support types; move helper types into dedicated files."
- "Repository persistence flow is copied between features; consolidate it behind one service."

## Anti-Patterns

- Creating a new service per screen with the same implementation.
- Moving duplicate code into a badly named `Utils` file.
- Extracting a service that still mutates SwiftUI view state directly.
- Splitting files by size alone while leaving responsibilities mixed.
- Moving everything into `Core` before there is real cross-feature reuse.

## Validation Checklist

- One shared implementation now owns the repeated workflow.
- Views and view models remain responsible for UI state only.
- New file names match the logic they contain.
- Package boundaries match responsibility and dependency direction.
- Service/system layers use `AppLog` rather than `print` when logging is needed.
- Tests cover the extracted business workflow at the service/coordinator layer when practical.
