---
name: persisted-data-evolution
description: Change the Alike Core Data model, UserDefaults keys, Codable blobs, and cached files without destroying data that users already have on disk.
---

# Persisted Data Evolution

Use this skill for any change to what Alike stores on a user's device.

Code can be reverted. **User data cannot.** With real installs in the field,
every store on disk was written by some previous release, and the app must keep
opening it.

## Repo Facts

- Store: Core Data, `Packages/Storage/Sources/Storage/PersistenceController.swift`.
- Model: `Packages/Storage/Sources/Storage/Resources/AlikeModel.xcdatamodeld`,
  currently a **single, unversioned** `.xcdatamodel` edited in place.
- Migration is fully automatic: `shouldMigrateStoreAutomatically` and
  `shouldInferMappingModelAutomatically` are both `true`.
- `loadPersistentStores` calls `fatalError` on failure — a migration the
  inference engine cannot express is not a degraded experience, it is a
  **launch crash for every user who has data**.
- Entities: `ClusterEntity`, `PhotoEntity`, `ScanMetadataEntity`.
- Opaque blobs inside the model: `featurePrintData`, `qualitySignalsData` —
  these are `Codable`/archived payloads and evolve under `Codable` rules, not
  Core Data rules.
- Version markers already in use: `scoringModelVersion`,
  `thumbnailConfigVersion`, `qualitySourceModificationDate` — the house pattern
  for invalidating derived values lazily instead of dropping rows.
- Non-Core-Data state lives in the `UserDefaults*Repository` types under
  `Packages/Storage/Sources/Storage/Repositories`.

## Trigger Conditions

- Adding, renaming, removing, or retyping anything in `AlikeModel.xcdatamodel`.
- Changing a relationship, its delete rule, or its optionality.
- Adding or changing a field in a `Codable` type that is stored as `Data`.
- Adding, renaming, or repurposing a `UserDefaults` key.
- Anything that would delete or reset stored rows, caches, or user labels.

## Workflow

1. Classify the change with `references/coredata-versioning.md` — **free**,
   **lightweight**, or **not inferable**.
2. If it is not "free", create a **new model version** rather than editing the
   current `.xcdatamodel` in place, and mark it current. Editing in place is
   only acceptable while a change is unreleased.
3. Prefer the lazy-invalidation pattern (a version marker plus re-measure) over
   deleting rows. See `references/coredata-versioning.md`.
4. For `Codable` blobs and `UserDefaults`, follow
   `references/userdefaults-and-blobs.md`.
5. Write the migration test **before** declaring the task done:
   `references/migration-testing.md`.
6. Verify on a simulator that already holds data from the previous release, not
   on a fresh install.

## Guardrails

- Never rename a Core Data attribute without a renaming identifier; without it,
  inference sees a drop plus an add and the old column's data is gone.
- Never make an existing optional attribute non-optional without a default —
  existing rows hold `nil` and the migration fails at launch.
- Never change an attribute's type in place. Add a new attribute, backfill,
  retire the old one a release later.
- Never delete an entity or attribute in the same release that stops using it.
- Never reuse a `UserDefaults` key or an enum raw value for a new meaning.
- Never resolve a migration problem by deleting the store. Destructive reset is
  R3 and needs explicit user authorization in the task; it wipes labels, scan
  history and cleanup history that the user cannot get back.
- Do not add a `fatalError` on any path a user's existing data can reach.
- Keep a single release's schema change in a single PR; a half-applied schema
  spread over two branches merges into a model nobody can migrate.

## Reference Map

| File | Use when |
|---|---|
| `references/coredata-versioning.md` | Model edits: what is inferable, how to version, how to rename safely |
| `references/userdefaults-and-blobs.md` | `Codable` payload fields, archived `Data` columns, defaults keys |
| `references/migration-testing.md` | Writing the test that proves the old store still opens |

## Related Skills

- `Skills/Architecture/change-safety/SKILL.md` — risk tiers and the extension-first rule
- `Skills/External/core-data-expert/SKILL.md` — depth on mapping models, persistent history, heavyweight migration
- `Skills/Testing/swift-testing/SKILL.md` — test placement inside `Packages/Storage`
