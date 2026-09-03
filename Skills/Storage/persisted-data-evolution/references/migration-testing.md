# Migration Testing

A schema or payload change is not done until a test proves that data written by
the **previous** release still loads. This is the only check that catches the
launch-crash class of bug, because `loadPersistentStores` calls `fatalError` in
`PersistenceController`.

Tests live inside `Packages/Storage/Tests`; follow
`Skills/Testing/swift-testing/SKILL.md` for structure and naming.

## 1. Fixture store test (Core Data schema changes)

Check a small store file, written by the previous model version, into the test
resources and open it with the current model.

1. Produce the fixture: run the **previous** release (or a checkout of it) on a
   simulator, seed a few clusters/photos, then copy the `.sqlite`, `.sqlite-wal`
   and `.sqlite-shm` files out of the app container.
2. Add them as test resources in `Packages/Storage/Package.swift`.
3. In the test: copy the fixture to a temporary directory (never open the
   resource in place — migration mutates the file), point an
   `NSPersistentContainer` at the copy with the same
   `shouldMigrateStoreAutomatically` / `shouldInferMappingModelAutomatically`
   settings as production, and load it.
4. Assert that loading produced **no error**, and that the expected row counts
   and a couple of representative attribute values survived.

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
