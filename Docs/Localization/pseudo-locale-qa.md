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

It also loads `Configuration/Alike.storekit`, the same StoreKit configuration the verbose debug
schemes use — without it the paywall sits in its unconfigured state and the plan cards, which are
some of the longest copy in the app, never render.

From the command line (quote the brackets so the shell does not glob them):

```bash
xcrun simctl launch <udid> com.alike.app -NSDoubleLocalizedStrings YES -NSShowNonLocalizedStrings YES -NSSurroundLocalizedStrings '[[]]'
```

A command-line launch has no StoreKit configuration, so use the scheme for the paywall screens.

`-NSShowNonLocalizedStrings` is the one to watch: anything appearing in CAPITALS is
a string that never reached a catalog, which after the task 39 split usually means a
key that failed to move into its package.

## Screens to walk

**Run the full pass from the `Alike-Pseudolocale` scheme.** The command line above is a
convenience for the non-paywall screens only — without the StoreKit configuration the paywall
never leaves its unconfigured state, and its plan cards carry some of the longest copy in the app.

Welcome onboarding · Scanner home · Cleanup progress and queue · Cleanup history ·
Cluster details and review bar · Settings (including the reminder rows) · User Guide hub
and a topic · **scheme only:** the four paywall entry points (post-first-scan, batch cleanup,
advanced filters, reminders).

## Findings — 2026-08-11 (task 40)

Both walks — the double-length pseudo-locale and the five real locales — are **still
owed**, for the same reason task 39 recorded: driving the simulator UI needs the native
simulator integration, which refuses to attach on this machine because `xcode-select`
points at `/Library/Developer/CommandLineTools` rather than a full Xcode. Unblocking it
needs a password, so it cannot be done from a session:

```bash
sudo xcode-select -s /Applications/Xcode-26.6.0.app/Contents/Developer
```

What *was* verified, on a booted simulator, with real German, French, Spanish and
Portuguese strings:

| Screen | Locales | Status | Note |
|---|---|---|---|
| Welcome, page 1 of 3 | `de` `fr` `es-419` `es` `pt-BR` | **Pass** | Launched per locale via `simctl launch … -AppleLanguages` and screenshotted. Title, body and the primary button reflow correctly; nothing clipped, nothing truncated, no English fallbacks. `de` and `pt-BR` keep the title on one line; `fr` wraps to two and the body to three, as designed. |
| Everything else | — | **Not walked** | `simctl` can launch and screenshot but cannot tap, so no screen past the first is reachable from here. |

Also checked, statically, across all eleven catalogs:

- Both `.lineLimit(1)` text labels are protected. `WelcomeView.swift:264` scales to 0.85
  with `allowsTightening`; the count badge at `CleanupView.swift:968` is a number scaling
  to 0.7 inside a 28pt frame.
- 106 strings run at 1.5× English or longer in `de` or `fr`. The longest ratios are short
  labels where the absolute length is small ("Make Best Shot" → "Définir comme meilleure
  photo", 14 → 29 characters). The ones worth watching on screen are the ones inside
  horizontal stacks: the Welcome navigation row, the cluster review action bar, and the
  paywall plan cards.

That is evidence of no *obvious* clipping hazard plus proof that the first screen renders
in every locale — not evidence that Cleanup, Details, Settings and the paywall survive.

## The walk that is still owed

Run each of these under the `Alike-Pseudolocale` scheme first (double-length catches the
worst case), then again per locale with the app language set in the scheme or via
`-AppleLanguages`. `de` and `fr` are the two that matter most; `pt-BR` is close behind.

- [ ] Welcome onboarding, pages 2 and 3 — including the **Grant Access** button, the
      longest primary label in the set (`de` "Zugriff erteilen", `fr` "Autoriser l'accès")
- [ ] Scanner home — idle, scanning, complete, error, and the free-scan allowance row
- [ ] Cleanup progress and queue — both cluster sections, all five badges, the filter and
      sort sheets
- [ ] Cleanup history — the all-time impact tiles and a month group
- [ ] Cluster details and the review bar — selection summary at 1, 2 and 5 selected, so the
      plural forms are seen rather than assumed
- [ ] Screenshot and blurred-photo cleanup — summary card and the delete confirmation
- [ ] Settings — every row, and the reminder day/time pickers
- [ ] User Guide hub and at least one topic
- [ ] **Scheme only:** all four paywall entry points (post-first-scan, batch cleanup,
      advanced filters, reminders), plus the disclosure block and both plan cards

Watch for anything in CAPITALS under the pseudo-locale scheme: `-NSShowNonLocalizedStrings`
marks a string that never reached a catalog.
