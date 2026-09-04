# Migration Testing

A schema or payload change is not done until a test proves that data written by
the **previous** release still loads. This is the only check that catches the
launch-crash class of bug, because `loadPersistentStores` calls `fatalError` in
`PersistenceController`.

Tests live inside `Packages/Storage/Tests`; follow
`Skills/Testing/swift-testing/SKILL.md` for structure and naming.

## 0. How to run these tests

`xcodebuild -workspace Packages/Storage -scheme Storage -destination 'id=<available simulator>' test`

Against the **package workspace**, not the app project — the app project's
`Storage` scheme is a library scheme with no test action. `tools/quick` and
`tools/full` run every package the same way.

## 1. Fixture store test (Core Data schema changes)

This already exists: `Packages/Storage/Tests/StorageTests/ModelVersionMigrationTests.swift`
opens `Fixtures/AlikeModelV1.sqlite` — a real store written by model version 1 —
with the model the app currently ships, and asserts the rows survive. Once a
version 2 model lands, that same test becomes a genuine v1 → v2 migration test
with no edits.

When a new model version ships, add a fixture for it:

1. Produce the fixture with a temporary test that builds a store from the
   **shipped** model version and seeds a couple of rows, then copy the resulting
   `.sqlite` into `Packages/Storage/Tests/StorageTests/Fixtures/AlikeModelV<N>.sqlite`
   and delete the generator. (Running the previous release on a simulator and
   copying its container works too, and is closer to real data.)
2. Ship only the `.sqlite`; the `-wal` and `-shm` files are checkpoint state and
   are recreated on open.
3. Resources are already declared: the `StorageTests` target processes `Fixtures`.
4. In the test: copy the fixture to a temporary directory (never open the
   resource in place — migration mutates the file), point an
   `NSPersistentContainer` at the copy with the same
   `shouldMigrateStoreAutomatically` / `shouldInferMappingModelAutomatically`
   settings as production, and load it.
5. Assert that loading produced **no error**, and that the expected row counts
   and a couple of representative attribute values survived.
6. Fetch through `NSManagedObject` and KVC rather than the generated subclasses,
   and never load a second copy of the model in-process: two `NSManagedObjectModel`
   instances claiming the same entity make `+[Entity entity]` ambiguous.

Keep fixtures tiny (a handful of rows). One fixture per shipped model version
that is still plausibly in the field.

## 2. Round-trip test (`Codable` blobs)

Cheaper and mandatory for any change to a stored payload type.

- Check in the **old encoded JSON** as a string/bytes literal in the test.
- Decode it with the current type; assert it succeeds and that the new field
  falls back to its default.
- Encode the current type, decode again, assert equality.
- Add one case for deliberately corrupt bytes: it must be handled as
  "not measured", not as a throw that escapes to a crash.

## 3. Absent-value test (`UserDefaults`)

- Construct the repository against a fresh, empty `UserDefaults` suite.
- Assert the default it reports is the behaviour existing users should see.
- Then write a value written in the **old** format (if the format changed) and
  assert it is still honoured.

## 4. Manual pass

Automated tests do not replace one manual run: install the previous release on
the simulator, create data, then install the branch build **over it** and open
the affected screens. A fresh install proves nothing about migration.

## Failure policy

If the migration test fails, the fix is never to delete the store or to lower
the assertion. Change the schema plan — usually to an additive attribute plus a
code backfill — and re-run.
