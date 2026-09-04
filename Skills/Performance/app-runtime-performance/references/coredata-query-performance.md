# Core Data Query Performance

Store: `Packages/Storage/Sources/Storage/PersistenceController.swift`
(an actor wrapping `NSPersistentContainer`, with `performBackgroundTask` for
off-main work). Repositories live in `Sources/Storage/Repositories`.

## Fetching

- Set `fetchBatchSize` on any fetch that can return more than a screenful
  (20–100 is the usual range). Without it, the whole result set is materialised
  at once. Most fetches in this repo currently set none — adding one is often
  the single biggest win.
- Set `fetchLimit` whenever only the first N rows matter.
- Use `propertiesToFetch` with `resultType = .dictionaryResultType` when only a
  few attributes are needed, so the blob columns (`featurePrintData`,
  `qualitySignalsData`) are never loaded.
- Use `includesPropertyValues = false` when only object IDs are needed (deletes,
  existence checks, counts).
- Prefer `count(for:)` over fetching and counting.
- Push filtering into the `NSPredicate`. Fetching everything and filtering in
  Swift loads every row and every blob.
- Use `relationshipKeyPathsForPrefetching` when the result is immediately walked
  through a relationship, instead of paying one fault per row.

## Writing

- Batch writes inside one `performBackgroundTask`, and save periodically
  (every few hundred objects) rather than once at the very end — one giant save
  spikes memory and blocks merges.
- Reset or drain the context between large batches so the row cache does not grow
  for the whole run.
- `NSBatchDeleteRequest` / `NSBatchUpdateRequest` bypass the object graph and are
  the right tool for bulk maintenance — but they skip validation and do not
  update in-memory contexts, so merge the resulting object IDs back into the
  view context afterwards.
- Never write on the view context in a loop.

## Main-thread contention

- `viewContext` is for reading what the UI shows. Analysis, imports and cleanup
  run on background contexts.
- A slow fetch on `viewContext` is a hang, not a delay; anything that can grow
  with library size belongs off the main actor.
- `automaticallyMergesChangesFromParent` is on, so a large background save
  produces merge work on the main thread — another reason to save in batches.

## Blob columns

`featurePrintData` and `qualitySignalsData` are the heaviest part of a row.
Fetch them only when they are about to be used; a list screen must never load
them. If a query needs them for many rows at once, that query is the problem.

## Before changing anything

Enable SQL logging (`-com.apple.CoreData.SQLDebug 1` in the scheme's arguments)
and look at the statements the slow path actually issues. Almost every Core Data
performance bug is visible there as "one query per row" or "select * on a table
with blobs" — guessing without it wastes the whole session.

Depth beyond this file: `Skills/External/core-data-expert/SKILL.md`.
