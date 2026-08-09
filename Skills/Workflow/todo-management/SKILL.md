---
name: todo-management
description: Create, review, audit, resolve, and report TODO-family comments without introducing untracked or stale technical debt.
---

# TODO Management

Use this skill when work involves adding, reviewing, auditing, resolving, or
reporting `TODO`, `FIXME`, `WARNING`, `HACK`, or `XXX` comments.

## Marker Semantics

- `TODO`: intentionally deferred work with a clear next action.
- `FIXME`: known incorrect behavior that requires correction.
- `WARNING`: a non-obvious safety or usage constraint; it is documentation,
  not a substitute for tracking work.
- `HACK`: a temporary workaround that should be removed.
- `XXX`: ambiguous; replace it with the specific marker that matches the intent.

## Comment Format

Write an actionable description that explains what remains and why it is
deferred. Committed actionable debt must include a ticket reference.

```swift
// TODO: Add paginated loading after the repository API supports cursors (PROJ-789)
// FIXME: Prevent duplicate saves during concurrent imports (PROJ-890)
// HACK: Keep the compatibility branch until the iOS 18 workaround is removed (PROJ-901)
// WARNING: Call only from the main actor; the dependency is not thread-safe.
```

An unreferenced actionable marker is allowed only during an active local change.
Before handoff, implement it, remove it, or attach a ticket. A factual `WARNING`
does not require a ticket unless it describes work that must be completed.

## Workflow

1. Search app source, packages, tests, and first-party skills:

   ```sh
   rg -n --hidden \
     --glob '!.git/**' \
     --glob '!Skills/External/**' \
     --glob '!**/.build/**' \
     --glob '!**/DerivedData/**' \
     --glob '!**/build/**' \
     '\b(TODO|FIXME|WARNING|HACK|XXX)\b' \
     Alike Packages Skills
   ```

2. Classify each match as actionable debt, a factual warning, or an
   instructional example in skill documentation.
3. For actionable markers, verify that the marker is specific, still relevant,
   and linked to a ticket before handoff.
4. Resolve straightforward work immediately when it is already in scope; do not
   create a marker merely to postpone it.
5. Report actionable markers separately from instructional examples and state
   explicitly when the actionable result is clean.

## Review Checklist

- [ ] The marker matches the documented semantics.
- [ ] The comment states a concrete next action and the reason it is deferred.
- [ ] Committed actionable debt includes a ticket reference.
- [ ] The surrounding implementation does not make the marker stale or false.
- [ ] `WARNING` documents a real constraint rather than hiding actionable work.
- [ ] `XXX` is replaced with `TODO`, `FIXME`, `WARNING`, or `HACK`.
- [ ] Instructional examples are not reported as repository debt.

## Guardrails

- Never add artificial markers to demonstrate this skill.
- Never use a marker instead of completing straightforward in-scope work.
- Never leave empty, vague, duplicated, or stale markers.
- Do not silently delete a valid marker; resolve its work or preserve its tracked
  context.
- An audit is read-only unless the user explicitly asks to add, update, resolve,
  or remove markers.

## Related Skills

- `Skills/Architecture/SwiftUIModular/references/code-documentation.md` — broader
  Swift documentation and comment conventions.
- `Skills/GitFlow/pr-agent-flow/SKILL.md` — pre-PR cleanup and follow-up reporting.
- `Skills/Meta/skill-authoring-governance/SKILL.md` — project skill structure.
