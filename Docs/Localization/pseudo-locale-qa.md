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

Walked with **RocketSim** (`/Applications/RocketSim.app/Contents/Helpers/rocketsim`), which
drives the Simulator over its own accessibility bridge and does not need the
`xcode-select` fix the native integration wants. `rocketsim elements --agent` reads the
localized accessibility tree directly, so a wrong or missing string shows up as text rather
than having to be spotted in a screenshot.

| Screen | Locales | Status |
|---|---|---|
| Welcome, pages 1–3 | `de` `fr` `es-419` `es` `pt-BR` | **Pass** |
| Scanner home (idle, free-scan allowance) | `de` `fr` | **Pass** |
| Cleanup, empty state | `de` | **Pass** |
| Settings, all sections | `de` `fr` | **Pass after a fix** — see below |
| Paywall: plan cards, disclosure block, both legal links | `de` `fr` | **Pass** |
| User Guide hub and a topic | `de` | **Pass** |

Notes worth keeping:

- **The paywall rendered with live StoreKit products** ($34.99 / $5.99) without the
  `Alike-Pseudolocale` scheme — the StoreKit configuration persists on the simulator once
  Xcode has run the app there. Both disclosure paragraphs render in full, and
  "Politique de confidentialité" + "Conditions d'utilisation" sit side by side on one row
  in French without clipping. That was the tightest layout risk in the set.
- **Nothing clipped anywhere.** Onboarding page 3 does overflow one screen in `de`, `fr`
  and `es` where English fits, but the page is inside a `ScrollView` and the whole text is
  reachable. (An earlier reading of this as clipping was a testing mistake: the swipe used
  screenshot-pixel coordinates against a 402×874-point canvas, so it never touched the
  scroll view.)
- Long-language compounds wrap correctly throughout — `Aufräum-Sitzungen`,
  `iCloud-Fotos gleicht die Änderung ab`, `Smarte Kategorien für Bildschirmfotos und
  unscharfe Fotos` all reflow rather than truncate.
- The tab bar holds `Scan · Aufräumen · Einstellungen` and `Analyse · Nettoyage · Réglages`
  at full size.

### The bug this walk found

`SettingsView.scheduleDescription` built the reminder row as `"\(weekday) at \(time)"` —
a hardcoded English " at " between two localized halves. German read **"Sonntag at 18:00"**,
and Ukrainian had been reading "Неділя at 18:00" since the feature shipped. It is now
`settings.main.reminderScheduleWeekdayTime` (`um` / `à` / `às` / `a las` / `о`).

This is exactly the class of defect the pseudo-locale scheme's `-NSShowNonLocalizedStrings`
is meant to surface, and it survived task 39's static sweep because the literal is not a
`Text("…")` — it is string interpolation inside a helper.

## Still owed

- The **double-length pseudo-locale pass** under the `Alike-Pseudolocale` scheme. RocketSim
  can drive it, but the scheme has to be launched from Xcode to inject the launch arguments;
  `simctl launch` can pass them too, and that is the cheaper route:
  `xcrun simctl launch <udid> com.alike.app -NSDoubleLocalizedStrings YES -NSShowNonLocalizedStrings YES -NSSurroundLocalizedStrings '[[]]'`
- Screens that need a **populated photo library**, which the simulator does not have: the
  cluster queue with real groups, cluster details and the review bar, the selection summary
  at 1/2/5 selected (where the plural forms actually render), screenshot and blurred-photo
  cleanup, the delete confirmations, and Cleanup history. Seed the simulator library first
  (`xcrun simctl addmedia`), then repeat the walk above.
- `pt-BR` and `es` past the Welcome screens.

Watch for anything in CAPITALS under the pseudo-locale scheme: `-NSShowNonLocalizedStrings`
marks a string that never reached a catalog. The reminder-row bug above is what one looks
like when nobody runs that pass.
