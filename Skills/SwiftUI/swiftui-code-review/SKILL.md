---
name: swiftui-code-review
description: >
  Review SwiftUI views for correct view graph, structure, initialization, lifecycle, rendering,
  and unnecessary update elimination. Use when asked to review, audit, or verify a SwiftUI view file
  against best practices.
---

# SwiftUI Code Review

## Trigger Conditions

- User asks to "review", "audit", or "check" a SwiftUI view
- A view has unexplained re-renders, jank, or update churn
- A new view is being added to the codebase and needs a quality gate
- A pull request touches SwiftUI view files

## Workflow

1. Read the target view file(s).
2. Work through the **Review Checklist** below, section by section.
3. Report each finding with: file path, line range, category tag, and a concrete fix.
4. Apply fixes when requested — keep behavior intact.
5. Run a build to confirm no regressions.

## Review Checklist

### 🏗 View Graph & Hierarchy
- [ ] `ForEach` uses stable, unique identifiers — never `id: \.self` on mutable/complex types
- [ ] Lazy containers (`LazyVStack`, `List`, `LazyHGrid`) used for long/dynamic lists
- [ ] No deep nesting of opaque `some View` closures that defeat type-checking
- [ ] Conditional branches use `@ViewBuilder` or `Group`; no `AnyView` erasure unless unavoidable
- [ ] Subviews receive only the data they need — not the whole parent state
→ Details: `references/view-graph-hierarchy.md`

### 📐 Structure & Ordering
- [ ] Members ordered: Environment → `let` → `@State` / stored props → computed vars → `init` → `body` → view builders → helper functions
- [ ] `private` applied to all non-public members
- [ ] Files >300 lines use `// MARK: -` sections and/or `private extension`
- [ ] Constants in `private enum UI { }` (not inline magic numbers)
- [ ] Related subviews in the same file unless reused elsewhere
→ Details: `references/view-structure-ordering.md`

### 🔧 Initialization
- [ ] `@State` view models initialized in `init` via `_vm = State(initialValue: VM(dep: dep))`
- [ ] No optional `@State` view models (`@State private var vm: VM?`)
- [ ] No `bootstrapIfNeeded` / lazy-setup anti-patterns
- [ ] Dependencies injected via `init` parameters, not captured from outer scope
- [ ] `@Environment` used for shared services; not re-declared as `let` props
→ Details: `references/initialization-patterns.md`

### 🔄 Lifecycle & Rendering
- [ ] `@MainActor` on every `View` struct (or on the whole module)
- [ ] `body` is a pure, side-effect-free description — no `print`, no mutations
- [ ] Async work triggered via `.task { }` (not `onAppear + Task { }`)
- [ ] Reactive re-fetching uses `.task(id: value)` — task cancels and restarts on change
- [ ] `.onChange(of:)` used for side effects only; does not duplicate `.task(id:)` work
- [ ] `.onAppear` / `.onDisappear` reserved for non-async side effects (analytics, focus)
→ Details: `references/lifecycle-and-rendering.md`

### ⚡ Update Minimization
- [ ] `ForEach` items conform to `Equatable` where possible, enabling diffing
- [ ] `@Observable` objects expose only the properties consumed by each view
- [ ] Closures passed into subviews are not recreated every render (prefer `let` callbacks)
- [ ] `.animation(_:value:)` preferred over unconditional `withAnimation` blocks
- [ ] Expensive computed vars (`filteredItems`, `sortedGroups`) not recomputed in `body`
- [ ] `EquatableView` / `drawingGroup()` applied only where profiling shows benefit
→ Details: `references/update-minimization.md`

## Decision Tree

1. Reviewing a net-new view?
   → Run all five checklist sections. Start with Structure, then Initialization.

2. View has unexpected re-renders?
   → Open `references/update-minimization.md` first, then Lifecycle.

3. ForEach crashes or shows wrong items?
   → Open `references/view-graph-hierarchy.md`.

4. `@State` / `@Observable` confusion?
   → Open `references/initialization-patterns.md` + `Skills/SwiftConcurrency/swift-concurrency-expert/SKILL.md`.

5. Lifecycle task leaks or double-fetch?
   → Open `references/lifecycle-and-rendering.md`.

## Guardrails

- Do not change business logic or layout during a review-only pass.
- Do not introduce a view model unless one already exists or is explicitly requested.
- Do not use `AnyView` to "fix" type errors — restructure the view graph instead.
- Do not add `print` or ad hoc logging inside `body`; use `AppLog` from `Packages/Core/Sources/Core/Logging/AppLog.swift` only in non-view layers when diagnostics are needed.
- Preserve all existing accessibility labels and traits.

## Related Skills

- `Skills/SwiftUI/swiftui-view-refactor/SKILL.md` — structural cleanup and reordering
- `Skills/SwiftUI/swiftui-performance-audit/SKILL.md` — profiling-backed perf fixes
- `Skills/SwiftUI/swiftui-magic-numbers/SKILL.md` — extracting inline constants
- `Skills/SwiftConcurrency/swift-concurrency-expert/SKILL.md` — actor isolation, Sendable
- `Skills/Meta/skill-authoring-governance/SKILL.md` — skill structure rules
