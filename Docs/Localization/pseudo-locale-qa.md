# Pseudo-locale QA

German and Turkish run 30–40% longer than English; Ukrainian is already longer in
places. The double-length pseudo-locale doubles every string, so a layout that
survives it survives any language we are likely to ship. Run this before paying a
translator, not after.

## How to run

Scheme **`Alike-Pseudolocale`** (shared, Debug) launches the app with:

```text
-NSDoubleLocalizedStrings YES     # every string rendered twice
-NSShowNonLocalizedStrings YES    # unlocalized strings render in CAPITALS
-NSSurroundLocalizedStrings [[]]  # brackets mark the boundaries of each string
```

From the command line:

```bash
xcrun simctl launch <udid> com.alike.app -NSDoubleLocalizedStrings YES -NSShowNonLocalizedStrings YES
```

`-NSShowNonLocalizedStrings` is the one to watch: anything appearing in CAPITALS is
a string that never reached a catalog, which after the task 39 split usually means a
key that failed to move into its package.

## Screens to walk

Welcome onboarding · Scanner home · Cleanup progress and queue · Cleanup history ·
Cluster details and review bar · Settings (including the reminder rows) · the four
paywall entry points (post-first-scan, batch cleanup, advanced filters, reminders) ·
User Guide hub and a topic.

## Findings — 2026-08-09

| Screen | Status | Note |
|---|---|---|
| Welcome, page 1 of 3 | Pass | Title, body and the Next button all reflow at +100%; no clipping, no capitalized fallbacks. Package catalogs resolve correctly (`Welcome_Welcome.bundle`). |
| Everything else | **Not yet walked** | See below. |

**This pass is incomplete.** Driving the simulator UI needs either the native
simulator integration — which is unavailable on this machine because `xcode-select`
points at `/Library/Developer/CommandLineTools` rather than a full Xcode — or
screen-control access to the Simulator app, which was declined for this session.
The remaining screens need a manual walk by someone with the simulator in front of
them; the scheme and the command above are all that pass requires.

What was checked instead, statically, across all packages:

- Every `.lineLimit(1)` on a text label (`WelcomeView.swift:264`,
  `CleanupView.swift:968`) is already paired with `minimumScaleFactor` and
  `allowsTightening`, so single-line labels shrink rather than clip.
- Every fixed `.frame(width:)` in the packages sizes an icon or a count badge
  (22–32pt), never a text run. The count badge at `CleanupView.swift:970` carries
  `minimumScaleFactor(0.7)`.

That is evidence of no *obvious* clipping hazard, not evidence of none — dynamic
layouts (HStacks of buttons, the paywall plan cards) can only be judged on screen.
