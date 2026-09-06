---
name: change-safety
description: Evolve shipped code by extension instead of modification; classify and gate breaking changes to public package APIs, persisted data, and user-visible state for an app with real installed users.
---

# Change Safety (extension over modification)

Use this skill whenever a change touches code that already shipped to users:
a `public` symbol in `Packages/*`, persisted data, user defaults, purchase or
entitlement state, or an existing user flow.

Alike has real installed users. Old app versions, old stores and old cached
payloads keep existing after every release. A change that only compiles is not
yet safe.

## Trigger Conditions

- Changing a `public` type, protocol, initializer, or function signature in a package.
- Adding a case to an existing `enum` that is switched over outside its package.
- Changing the meaning, default, or unit of an existing stored value.
- Renaming or removing anything persisted: Core Data attributes, `UserDefaults`
  keys, `Codable` payload keys, file names under Application Support.
- Reworking a flow users already know (navigation, paywall, scan, cleanup).

## Core Rule

**New behaviour arrives as new code. Existing behaviour is modified only with a
stated reason and a compatibility plan.**

1. First try: a new type, a new protocol conformance, a new package, a new
   `enum` case handled behind a default, a new optional attribute.
2. Second try: a new parameter **with a default value** so existing call sites
   and existing serialized data stay valid.
3. Only then: change the existing symbol or field in place — and only after the
   checklist in `references/breaking-change-checklist.md`.

Modification is not forbidden; it is a decision that must be named in the commit
and PR body, not a side effect of an implementation detail.

## Risk Tiers

| Tier | Example | Gate |
|---|---|---|
| **R0 — internal** | private/internal code inside one package, no stored data | Normal review |
| **R1 — cross-package** | `public` API used by another package or the app target | Prefer additive; if breaking, update all call sites in the same PR |
| **R2 — persisted** | Core Data schema, `UserDefaults` keys, `Codable` blobs, cached files | Use `Skills/Storage/persisted-data-evolution/SKILL.md`; a migration test is mandatory |
| **R3 — irreversible for the user** | deleting user data, invalidating purchases, resetting scan history, wiping labels | Explicit user confirmation in the task, plus a documented rollback |

Never silently upgrade a change from R0 to R2 by "just adding a field to the
entity". Say the tier out loud in the PR body when it is R2 or R3.

## Workflow

1. Classify the tier before writing code.
2. For R1+, list every call site / stored consumer of the symbol you touch.
3. Choose the additive shape from `references/extension-first.md`.
4. If you must modify: fill the checklist in `references/breaking-change-checklist.md`.
5. For R2, follow `Skills/Storage/persisted-data-evolution/SKILL.md` and add the
   migration test before the feature work is called done.
6. State the tier and the compatibility decision in the commit message and PR body.
7. Before merging anything R1 or higher, walk the pre-merge gate in
   `references/release-compatibility-gate.md`. It is a checklist, not advice.

## Guardrails

- Do not remove a persisted key in the same release that stops writing it.
  Stop writing first, read-with-fallback for at least one release, delete later.
- Do not repurpose an existing key, attribute, or `enum` raw value for new
  meaning. Old installs will read the old meaning. Add a new one.
- Do not change a default that already shaped user data (thresholds, quality
  cut-offs, scoring weights) without a version marker beside it — the repo
  already does this with `scoringModelVersion` and `thumbnailConfigVersion`;
  follow that pattern instead of inventing a new one.
- Do not make a `switch` over a shipped `enum` exhaustive across package
  boundaries when new cases are expected; give it a default path.
- Do not use `fatalError` on a path that a user's existing data can reach.
- Feature-flag risky reworks behind a build configuration flag
  (`Skills/Architecture/SwiftUIModular/references/xcode-schemes-configurations.md`)
  so the old path stays reachable in the same binary.
- A refactor PR changes structure or data, never both.

## Reference Map

| File | Use when |
|---|---|
| `references/extension-first.md` | Choosing the additive shape: protocol, default parameter, new type, new case |
| `references/breaking-change-checklist.md` | You decided modification is unavoidable |
| `references/release-compatibility-gate.md` | The hard MUST/NEVER rules and the pre-merge gate — read before merging anything R1+ |

## Related Skills

- `Skills/Storage/persisted-data-evolution/SKILL.md` — R2 changes (the dangerous ones)
- `Skills/Architecture/SwiftUIModular/SKILL.md` — package boundaries and DI that make extension possible
- `Skills/GitFlow/pr-agent-flow/SKILL.md` — review pass and PR body
- `Skills/Testing/swift-testing/SKILL.md` — locking behaviour with a regression test
