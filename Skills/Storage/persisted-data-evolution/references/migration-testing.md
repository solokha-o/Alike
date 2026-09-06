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

The `-workspace` argument here is the `Packages/Storage` **directory itself**,
not a checked-in `.xcworkspace` — there isn't one; Xcode treats an SPM package
directory as an implicit workspace and generates the scheme on the fly. That
only works under full Xcode, so this requires `xcode-select` to point at a full
Xcode install, not the Command Line Tools. If it points at the Command Line
Tools, prefix the command inline instead of changing the global selection:

`DEVELOPER_DIR=/Applications/Xcode-<version>.app/Contents/Developer xcodebuild -workspace Packages/Storage -scheme Storage -destination 'id=<available simulator>' test`

With the Command Line Tools selected (no `DEVELOPER_DIR` override), the exact
failure is:

```
xcodebuild: error: 'Packages/Storage' is not a workspace file.
```

That signature means the toolchain, not the command, is wrong — the workspace
argument is correct.

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
2. Close the store before copying anything: remove it from the
   `NSPersistentStoreCoordinator` (`remove(_:)` checkpoints a WAL-mode store on
   close, folding `-wal` back into the main file). A WAL-mode store can hold
   committed rows **only** in `-wal` — they are not reconstructed from the
   `.sqlite` file alone, so copying while the store is still open, or open in
   another process, silently ships an empty or truncated fixture. Then verify
   the standalone `.sqlite` actually holds the seeded rows before discarding the
   sidecars:

   `sqlite3 Fixtures/AlikeModelV<N>.sqlite "select count(*) from ZPHOTOENTITY;"`

   Only once that count matches what you seeded, ship the `.sqlite` alone and
   discard the `-wal` / `-shm` sidecars — they must never be committed next to
   a fixture.
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
