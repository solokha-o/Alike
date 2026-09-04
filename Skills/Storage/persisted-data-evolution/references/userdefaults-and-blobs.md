# `UserDefaults` Keys and Archived Blobs

Two stores in the repo are *not* governed by Core Data migration but are just as
persistent:

- The `UserDefaults*Repository` types in
  `Packages/Storage/Sources/Storage/Repositories`.
- `Data` columns holding encoded payloads: `qualitySignalsData`,
  `featurePrintData`.

Neither gets a migration engine. Compatibility is entirely on the decoding code.

## `Codable` payloads inside `Data`

Rules, in order of importance:

1. **New fields are optional, or have a default.** A non-optional field added to
   a `Codable` struct makes every previously written payload fail to decode.

   ```swift
   struct QualitySignals: Codable {
       let sharpness: Double
       let exposure: Double
       var faceScore: Double?   // added later — optional, so old blobs decode
   }
   ```

2. **Never repurpose a coding key.** An old payload holding the old meaning will
   decode into the new field and be silently wrong. Add a new key.

3. **Never change a field's type in place.** Add a new key, read either, prefer
   the new one, stop writing the old one a release later.

4. **A decode failure must not be fatal.** Treat an undecodable blob as "not
   measured yet" and re-derive it, exactly as a stale version marker is handled.
   `try?` plus re-measure, never `try!` and never `fatalError`.

5. **Version the payload when its shape genuinely changes.** Add a `version`
   field, or bump the existing marker column beside it, so the reader knows
   which shape it holds instead of guessing from which keys are present.

6. Prefer `JSONEncoder`/`Codable` over `NSKeyedArchiver` for new payloads —
   archived class graphs break on class renames and module moves.

## `UserDefaults` keys

- Key strings are a public contract with past releases. Once shipped, a key
  string is permanent.
- Renaming a key silently resets the value to the default for every existing
  user. If a rename is required: read old → write new → keep reading old as a
  fallback for one release → remove the fallback later.
- Do not repurpose a key. Purchase, rating-prompt, premium-prompt and scan-usage
  keys drive user-visible gating; a repurposed key can re-show a paywall or a
  rating prompt to users who already dismissed it.
- New keys must behave correctly when **absent**. The absent value is what every
  existing install has, so the default is the real shipping behaviour — test
  that path, not the freshly-written one.
- Removing a key: stop writing it first, delete the read a release later. Do not
  bulk-remove defaults in a cleanup pass.

## Files on disk

Cached files under Application Support / Caches follow the same rules: a
filename or directory layout that shipped is a contract. Write to a new path
rather than reinterpreting an old one, and tolerate the old path being present
(or absent) without crashing.
