# Lock Screen widgets — QA record (1.5.0)

Stage 4 of the Lock Screen feature. Stages 1–3 shipped the three accessory
layouts of `AlikeStatusWidget` and the `libraryTotalBytes` that draws the ring
(PRs #86, #87, #88). This is where they are proven, and where the next release's
pass starts from instead of from nothing.

## 1. Why the evidence is split three ways

The simulator cannot form clusters and never sets `photoScreenshot`, so no state
past "never scanned" can be reached by using the app there. What it can do is
render any state faithfully, because the extension reads a file: stage the file,
reinstall, look at the Lock Screen. That covers layout, wording, the ring, the
appearance modes and the locales.

What it cannot answer is the part that depends on a real library or real
hardware: how long the scan takes now that it sums the library, what the ring
reads against a real reclaimable estimate, what the extension costs in memory
with every widget placed, StandBy, VoiceOver, and whether an install upgraded
from 1.4.1 keeps its home widgets and its snapshot. Those are §5 and §6.

Everything a unit test can settle is settled in `WidgetSupportTests` instead of
in either pass — §3 says which row each test retires.

## 2. Staging a state

```sh
python3 tools/stage_widget_snapshot.py hasSuggestions \
  --udid <simulator> --app <path/to/Alike.app> --screenshot out.png
python3 tools/stage_widget_snapshot.py --list
```

The order is terminate → write the file → `simctl install` → **never launch**. A
launch makes `WidgetSnapshotPublisher` republish from the simulator's own empty
library, and the hand-written state is gone before it is seen. The reinstall is
what reloads the timelines; accessory widgets then take about 25 seconds to
redraw, so the script waits 30 before it captures.

The widget gallery is not a preview of any of this — `getSnapshot` returns
`WidgetSnapshot.placeholder()` whenever `context.isPreview` — so a state is only
visible once the widget is placed. Placing them: LOCK twice, hold the wallpaper
3 s, Customize → the Lock Screen face → ADD WIDGETS for circular and
rectangular, and the date row above the clock for inline.

`--appearance dark|light` and `--content-size accessibility-medium` re-render in
place without restaging.

## 3. Coverage map

| Checklist row | Where it is settled |
|---|---|
| Three families × seven states | **Test** `WidgetAccessoryCompositionTests` (families, glyphs, destinations, VoiceOver, per-slot invariants) + **simulator** §4 for what it looks like |
| Circular: ring matches the share | **Test** `circularShare`, `circularShareIsClamped`, `circularReview` |
| Circular: no `libraryTotalBytes` → no ring, no crash | **Test** `circularShare` + `WidgetSnapshotCodecTests` (1.4.x payload decodes) + **simulator** `legacy141` |
| Circular: the figure fits the ring | **Test** `circularFigureBudget` |
| Rectangular: third line is the action | **Test** `rectangularAlwaysActs`, `rectangularActions`, `rectangularNoEchoedAction` |
| Rectangular: stale → date | **Test** `staleTransitionShowsTheDate`, `rectangularDates`; the timeline entry that triggers it: `WidgetPresentationTests` |
| Rectangular: `ViewThatFits` at AX sizes | **Simulator** (`--content-size`) — no test reaches a rendered view |
| Inline: not truncated in 13 locales | **Test** `testInlineAccessoryLinesFitTheSlotInEveryLanguage` (26-character budget) + `testEveryInlineAccessoryCaptionIsSampledByTheBudget` (no state escapes the sample); **simulator** spot-check de/pl/ar |
| Inline: RTL | **Simulator** (ar) |
| Tinted/vibrant, light/dark | **Simulator** |
| StandBy (circular/rectangular) | **Device** — the simulator has no StandBy |
| Tap → the right `alike://` route | **Test** `destinationRoundTrips`, `destinationMatchesPresentation`; cold/warm launch and Premium vs free: **device** |
| Stale after 24 h without opening the app | **Test** `staleTransitionShowsTheDate`; the real 24 h: **device** |
| VoiceOver reads figure, unit, action, date | **Test** `everyStateSpeaks`, `rectangularLabel` pin the strings; the spoken order: **device** |
| Extension memory, all widgets placed | **Device** |
| Scan cost after stage 3 | **Device**, on a real large library |
| Ring after scan / cold launch / delete local data | `Packages/Cleanup/.../CleanupWorkspaceLibraryTotalBytesTests` covers the workspace's half; the last link is **device** |
| Upgrade from 1.4.1 with data kept | **Device**, step 1 of §5 — and it is destroyed by the first clean reinstall |
| `tools/full`, release-compatibility gate | §7 |

## 4. Simulator findings

iPhone 18 Pro, iOS 27.0, `develop` at `3539f8e` + this branch, Release build,
locale en, 18 September 2026. Circular and inline were placed together (a
rectangular widget fills the whole slot, so it cannot share it with a circular
one); the rectangular pass repeats the matrix after swapping the slot. States
staged with `tools/stage_widget_snapshot.py`.

| State | Circular | Inline | Rectangular |
|---|---|---|---|
| `hasSuggestions` | ring ≈7 % (1,93 GB of 27,9 GB), figure `1,93 GB` under the brand glyph | `≈1,93 GB to clean up` | `Alike` / `≈1,93 GB` / `Review`, no date |
| `hasSuggestionsStale` | unchanged from fresh | unchanged from fresh | `≈1,93 GB` / `Scanned 18 Sep 2026` / `Review` — title dropped for the date |
| `resumeReview` | ring 60 %, `18/30` | `Review: 18 of 30` | `18 of 30` + progress bar / `Continue` |
| `libraryChanged` | ring and figure as `hasSuggestions` | `≈1,93 GB to clean up` | as `hasSuggestions` |
| `allCaughtUp` | `checkmark` instead of the figure, glyph kept, no ring | `All clean` | `All clean` / `Scanned 18 Sep 2026` / `Open Alike` |
| `neverScanned` | glyph only, no figure, no ring | `Scan` | `Alike` / `Scan` — no headline, the action is not echoed |
| `noAccess(.limited)` | ring and figure — limited access still has figures, for the shared photos | `≈1,93 GB to clean up` | as `hasSuggestions` |
| `noAccess(.denied)` | `lock.fill`, no figure, no ring | `Open Alike` | `Alike` / `Open Alike` |
| `unavailable` (no file) | `lock.fill`, no figure, no ring | `Open Alike` | `Alike` / `Open Alike` |
| `legacy141` (1.4.1 payload) | figure `1,93 GB`, **no ring** | `≈1,93 GB to clean up` | as `hasSuggestions` |

**Passes.** Every state renders on all three families; the priority is the
`displayState` one; the ring matches the share and is absent — not zero — for a
1.4.1 payload; the rectangular slot always ends on the action and dates itself
only when stale or all-caught-up; `ViewThatFits` drops the `Alike` title exactly
when the slot needs the room (the stale date, the progress bar) and keeps it
otherwise.

**Findings.**

- The inline slot shares its row with the date, and iOS shortens the date to fit:
  `Fri 18 Sep` became `Fri 18` in every inline shot. Expected system behaviour,
  not truncation of our line — worth knowing before someone reports it as a bug.
- At `accessibility-extra-large` the system text around the widgets grows but the
  accessory slots keep their own metrics, so the rectangular layout is unchanged
  and `ViewThatFits` is never pushed to its second branch on this device. The AX
  row therefore stays a device check rather than a settled one.
- Accessory slots redraw about 25–30 s after a reinstall; a screenshot taken
  earlier catches the placeholder skeleton, which looks like a broken layout and
  is not one. The script's 30 s wait is the minimum that worked, and a change of
  `content_size` needs longer still.

## 5. Device runbook

Ordered so each step leaves the state the next one needs. Record per row: device
model and iOS version, a screenshot (or the number, for steps 3 and 10),
pass/fail, and any finding written out in §6.

1. **The upgrade, before anything else.** Install 1.4.1, scan, confirm both home
   widgets render. Then install the 1.5.0 build **over it**, without deleting the
   app. Expected: home widgets unchanged, the widget still reads the snapshot
   1.4.1 wrote, and the circular slot draws **no ring** until the next scan —
   that payload carries no `libraryTotalBytes`. This is MUST #5 of the gate and
   the first clean reinstall destroys the evidence, so it is step 1.
2. Place all three accessory widgets and both home widgets on that device.
3. **Scan the real library.** From Console take
   `Library total bytes measured. assets=… duration=…`
   (`Packages/PhotoAnalysis/Sources/PhotoAnalysis/PhotoAnalysisServiceImpl.swift:219`)
   and the whole scan's duration. Run the same scan on 1.4.1 for the baseline and
   record both — a performance claim without the measurement is not made.
4. **The ring's life:** after the scan (ring present, share plausible against
   reclaimable ÷ library), after a cold launch (ring survives), after deleting
   local data in Settings (ring gone, no crash).
5. The states real use reaches: hasSuggestions, resumeReview, libraryChanged,
   allCaughtUp, neverScanned, noAccess limited **and** denied (revoke in
   Settings), unavailable.
6. Tinted and vibrant, light and dark, StandBy for circular and rectangular.
7. de, fr, pl, ar: the inline line is not truncated, ar mirrors.
8. Taps: each family, cold launch and warm, on a Premium and on a free account.
9. VoiceOver: each family reads the figure, its unit, the action and the date as
   one sentence.
10. Extension memory: Instruments (Allocations) on `AlikeWidgets` with every
    widget placed; record the peak.
11. Stale: a day without opening the app, then confirm the rectangular slot has
    moved to the dated wording by itself.

## 6. Device findings

_Not yet run._ Fill in as §5 is walked; the stage is not done until this section
carries the scan-duration comparison against 1.4.1 and the extension's memory
peak.

| Step | Device / iOS | Result | Finding |
|---|---|---|---|
| | | | |

## 7. Release-compatibility gate

Walked against
`Skills/Architecture/change-safety/references/release-compatibility-gate.md`.

**Tier R1 — additive throughout.** A new optional `Codable` field
(`libraryTotalBytes`; `schemaVersion` deliberately stays 1), three accessory
cases added to `WidgetLayoutFamily`, and three families joined to the
`supportedFamilies` of the existing `AlikeStatusWidget` — whose `kind` string is
frozen, so widgets already on a home screen keep working. Nothing was renamed,
retyped or repurposed, and no schema change rides along with a feature change.

- **Old stored data still loads — by test, not reasoning.**
  `WidgetSnapshotCodecTests` decodes a 1.4.x payload that has no
  `libraryTotalBytes` key; `WidgetPhotoAuthorization` and `WidgetSessionProgress`
  both decode leniently, so an unknown future value degrades instead of throwing.
- **Defaults for absent values.** No `libraryTotalBytes` means **no ring**, not a
  ring at zero — `WidgetComposition.share(of:in:)` returns `nil` when either side
  is unknown. A zero ring would read as "nothing to clean" when the truth is "not
  measured". That is what every 1.4.1 install has today, and `circularShare`
  pins it.
- **Manual pass over pre-existing data.** §5 step 1, on a device upgraded from
  1.4.1 without deleting the app. The gate is not signed off on a fresh install.
- **Rollback.** A user who goes back to 1.4.1 has a snapshot carrying one extra
  JSON key, which that release's decoder ignores; the accessory placements
  disappear with the extension that drew them. No data is lost either way.
- **Deprecation window.** None opened — nothing stopped being written, no key or
  attribute is on its way out.
- **Full compile.** `tools/full` green on 18 September 2026 with an explicit
  `ALIKE_BUILD_DESTINATION` (iPhone 17 Pro Max, iOS 27.0): whitespace, all
  eighteen packages, the metadata bundle, and the `xcodebuild Alike build` gate —
  `build/reports/local-ci/20260918T170342Z-69104/`.

Version stays 1.4.1 (build 11) here. The bump to 1.5.0 (12) belongs to stage 5,
and doing it here would make this a release PR.
