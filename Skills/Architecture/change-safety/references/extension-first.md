# Extension-First Patterns

Concrete additive shapes, in the order to try them.

## 1. New parameter with a default

Existing call sites keep compiling; existing serialized values keep decoding.

```swift
// Before
public init(threshold: Double)

// After — additive
public init(threshold: Double, minimumSharpness: Double = 0.35)
```

Do **not** reorder existing parameters while adding one. Reordering is a source
break for every caller and produces a noisy diff that hides the real change.

## 2. New protocol instead of a wider one

A feature that needs one extra capability gets its own small protocol rather
than a new requirement on the shipped one.

```swift
// Wrong: every existing conformer must now implement this.
public protocol PhotoRepository {
    func photos() async throws -> [Photo]
    func prune(before: Date) async throws   // <- breaks all conformers
}

// Right: additive capability, composed where needed.
public protocol PhotoPruning {
    func prune(before: Date) async throws
}
```

If the requirement genuinely belongs on the existing protocol, give it a default
implementation in a protocol extension so conformers outside the package stay
valid.

## 3. New type beside the old one

For a reworked algorithm or screen, add `BestShotScorerV2` (or a new package
feature) and select between them, instead of rewriting the shipped type in
place. Delete the old one in a later, separate commit once the new path is
proven on real data.

This is also how the repo already handles model changes: a version marker
(`scoringModelVersion`, `thumbnailConfigVersion`) records which producer wrote a
stored value, so old rows stay readable and are re-measured lazily rather than
being invalidated wholesale.

## 4. New enum case, non-exhaustive consumers

Adding a case to a shipped `public enum` breaks every exhaustive `switch` in
other packages and in the app target.

```swift
// In the consumer, from the start:
switch state {
case .idle:      ...
case .scanning:  ...
default:         ... // tolerate cases added later
}
```

For persisted enums also pin the raw value and never reuse one:

```swift
public enum CleanupCategory: String {
    case screenshots   // raw value "screenshots" is now permanent
    case duplicates
    case blurry        // added later; old installs simply never wrote it
}
```

Decoding must tolerate an unknown raw value (map to a neutral case), because a
newer app version, a restored backup, or a synced payload can produce one.

## 5. New optional attribute instead of a changed one

For Core Data and `Codable` payloads, an added **optional** attribute with no
default is the only reliably free change. See
`Skills/Storage/persisted-data-evolution/references/coredata-versioning.md`.

## 6. Dependency injection instead of an `if`

When behaviour must differ per context, inject a collaborator through the
existing protocol seam rather than adding a boolean parameter that every caller
must now reason about. Booleans accumulate; protocol seams stay testable.

## When extension is the wrong answer

Do not add a fourth parallel implementation of the same idea to avoid touching
the third. If a type has grown two "V2" siblings, the honest move is a single
modification with the full checklist, not another sibling.
