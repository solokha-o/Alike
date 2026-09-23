# Triage an App Store crash from Xcode Organizer

## Where the logs are

Organizer (Window → Organizer → Crashes) downloads each crash point to:

```
~/Library/Developer/Xcode/Products/com.alike.app/Crashes/Points/<point-id>.xccrashpoint/
  Filters/Filter_<point-id>-…/Logs/<date>_<time>-<hash>.crash
```

`<point-id>` is the identifier Organizer shows for the crash group, for
example `sq7WDHJt-BgHYvLVs5W7_`. Every `.crash` file under it is one report.
Each one is plain text, so you can read it with `grep` and `sed`:

```bash
find ~/Library/Developer/Xcode/Products/com.alike.app/Crashes/Points/<point-id>.xccrashpoint -name '*.crash'
grep -n -A25 'Crashed:' <file>.crash
grep -n '^Version:\|^OS Version:\|^Hardware Model:\|^Exception Type:' <file>.crash
```

## Reading one

- Find the thread that crashed from `Thread N Crashed:`, not from thread 0.
  A background crashed thread with SwiftUI frames beneath it usually means
  async rendering or layout.
- The first `Alike` frame is the one to look at. System frames above it say
  *how* the process stopped. For example,
  `_dispatch_assert_queue_fail` ← `_swift_task_checkIsolatedSwift` is a
  failed main-actor isolation check. See
  `Skills/SwiftConcurrency/swift-concurrency-expert/references/swiftui-offmain-layout-isolation-trap.md`.
- Build a table with date, version (build), device, iOS version and the
  first `Alike` frame for every report. The signature has to match across
  the reports before you treat them as one bug.
- `NO_CRASH_STACK` in the point's name is the group's label only, not a
  diagnosis. Read the logs.

## Symbols

- Organizer symbolicates a report when the dSYM for that exact build is
  available locally. Download one with `tools/dsyms X.Y.Z BUILD`.
- **Builds 1.3.0 and earlier have no uploaded dSYMs.** Their `Alike` frames
  stay as raw addresses. Match their signature (system frames, crashed
  thread, SwiftUI frames) against a later symbolicated report of the same
  point.
- To resolve one frame by hand, run
  `atos -arch arm64 -o <Alike.app.dSYM>/Contents/Resources/DWARF/Alike -l <load address> <frame address>`.
  The load address is on the `Alike` line under `Binary Images:`.
- `tools/symbolicate <payload.json>` is for **MetricKit** payloads, the
  ones users send from the crash-report sheet added in 1.6.0. It does not
  handle Organizer `.crash` files.

## After the fix

- Record the point id in the fix's commit and PR, and in its Notion card.
- Once the build containing the fix ships, check that the point receives no
  new reports from that version or later.
