# Core Data Model Versioning

## Classification

Decide which bucket the edit falls into **before** touching the model.

### Free — no migration concern

- Adding a new **optional** attribute.
- Adding a new entity that nothing existing points to.
- Adding a new **optional, to-many** relationship.
- Changing anything that is not persisted: fetch request templates, derived
  Swift helpers, `@objc` accessors, computed properties.

### Lightweight — inferable, still needs a new model version

- Adding a non-optional attribute **with a default value**.
- Renaming an entity or attribute **with a renaming identifier set** on the new
  version's element (the old name goes in `Renaming ID`).
- Removing an attribute or entity (data in it is dropped — confirm that is
  intended and that nothing reads it).
- Making a required attribute optional.
- Adding a relationship, or changing a to-one to a to-many.

### Not inferable — needs a mapping model or a staged plan

- Changing an attribute's **type** (`String` → `Int`, `Data` → `String`, …).
- Making an optional attribute required without a default.
- Splitting one entity into two, or merging two into one.
- Any change whose new value must be *computed* from the old data.

For this bucket, do not fight the inference engine: add the new attribute
alongside the old one, backfill in code on first launch after the update, and
retire the old attribute in a later release. That is a lightweight migration
plus ordinary code, and it is revertible. A custom `NSMappingModel` is the last
resort — see `Skills/External/core-data-expert/references/migration.md`.

## Creating a new version

The model is currently a single unversioned `.xcdatamodel`. Editing it in place
is acceptable **only** for a change that has not shipped yet. Once a change is
in a release, the next schema edit gets its own version:

1. In Xcode, select `AlikeModel.xcdatamodeld` → Editor → **Add Model Version**,
   based on the current version. Name it `AlikeModel 2` (then `3`, …).
2. Make the edits in the **new** version only. Never touch a shipped version.
3. Set the new version as current (`Model Version` in the file inspector); this
   writes `.xccurrentversion` inside the `.xcdatamodeld` bundle.
4. Confirm the `.xcdatamodeld` bundle is still picked up as a package resource
   by `Packages/Storage/Package.swift` — a new version directory must ship too.
5. Commit the whole `.xcdatamodeld` bundle in one commit, with the schema change
   described in the message.

## Renaming safely

An attribute rename without a renaming identifier is silent data loss: the
inference engine sees the old attribute removed and a new empty one added.

- Set `Renaming ID` on the new version's attribute to the **old** name.
- If a rename is not worth this ceremony, do not rename. A slightly stale
  attribute name is cheaper than a lost column.

## Lazy invalidation over deletion

When a change alters how a derived value is produced (scoring, thumbnails,
feature prints), do not delete the rows. Follow the pattern already in the
repo:

- Keep a version marker column beside the derived value
  (`scoringModelVersion`, `thumbnailConfigVersion`).
- On read, compare the stored marker with the current one.
- If it is stale, re-measure that item and write the new marker.

Cost is spread over use, old rows stay valid until they are re-measured, and a
revert simply stops re-measuring instead of leaving a hole.

## Delete rules and relationships

Changing a relationship's delete rule is a behaviour change, not a schema
detail: switching to `Cascade` can remove rows the previous release kept.
Treat a delete-rule change as R3 in `Skills/Architecture/change-safety/SKILL.md`
and justify it explicitly.
