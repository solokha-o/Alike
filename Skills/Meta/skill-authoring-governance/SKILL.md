---
name: skill-authoring-governance
description: Create or evolve project skills with fast discovery, reference decomposition, and repo logging policy alignment.
---

# Skill Authoring Governance

Use this skill when creating a new skill or refactoring an existing one that has grown too large.

## Trigger Conditions

- A new skill is requested for a recurring workflow.
- An existing `SKILL.md` is too long to scan quickly.
- A skill contains multiple independent topics and selection is getting slower.
- Skill updates must enforce project-wide logging conventions.

## Workflow

1. Identify whether to create a new skill or evolve an existing one.
2. Keep `SKILL.md` as a thin index: triggers, short workflow, decision tree, guardrails.
3. Move examples, deep recipes, edge cases, and anti-patterns into `references/*.md`.
4. Add "Related Skills" links for fast cross-skill routing.
5. Add or verify explicit "Logging Policy" rules for service/system work.

## Decomposition Rules

- If `SKILL.md` is ~180-220+ lines, split content into `references/`.
- If there are more than 3 independent themes, split by theme into separate reference files.
- Prefer many short reference files over one long monolithic document.
- Keep top-level instructions stable; move volatile details into references.

## Decision Tree

1. Is this a brand-new workflow used across tasks?
If yes: create a new skill scaffold.
If no: continue.

2. Is existing `SKILL.md` still fast to parse (<180 lines and focused)?
If yes: update in place.
If no: decompose into `references/` and keep `SKILL.md` as an index.

3. Does the skill involve new services/repositories/backends?
If yes: add/verify Logging Policy with `Packages/Core/Sources/Core/Logging/AppLog.swift` usage and safe metadata rules.

## Guardrails

- Do not duplicate full reference content inside `SKILL.md`.
- Do not keep large code snippets in `SKILL.md`; move them to `references/`.
- Do not allow runtime `print` in production-oriented patterns.
- Prefer explicit file paths for templates and scripts.

## Logging Policy

- For new services/systems/repositories, use project logging via:
  - `Packages/Core/Sources/Core/Logging/AppLog.swift`
- Log key lifecycle events (start/success/failure) with structured metadata.
- Avoid dumping sensitive values into logs; prefer summary/length-only metadata.
- Do not use runtime `print` for production diagnostics.

## Template Structure

Recommended structure for each scalable skill:

- `SKILL.md`
- `references/components.md`
- `references/testing.md`
- `references/logging-policy.md` (when applicable)
- `scripts/` (only if it removes repeated manual steps)

## Related Skills

- `Skills/Architecture/SwiftUIModular/SKILL.md`
- `Skills/Testing/swift-testing/SKILL.md`
- `Skills/SwiftUI/swiftui-view-refactor/SKILL.md`
