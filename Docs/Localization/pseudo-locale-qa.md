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

## Findings — 2026-08-11, German and French on a real library

The user walked the library-dependent screens on their own iPhone with the app language set
per-app (Settings → Alike → Language), and sent screenshots. Everything below is from a real
photo library with 70+ clusters.

**Pass:** the cleanup queue and its two sections, the smart-category rows, all badges
(`Nicht geprüft` / `In Prüfung` / `Non examinés` / `En cours d'examen`), the "library changed"
card, cluster details, the summary card at 1 and at 15 selected, the review action bar at 1
and 15, the cleanup progress screen, and the history screen with real entries. No clipping,
no truncation, no overlap — German holds `15 Fotos bewegen` and
`15 ausgewählt, geschätzte Größe 68,6 MB.` on one line each.

**Two defects, both fixed:**

1. **The post-cleanup toast was never a plural.**
   `cleanup.main.photosMovedToRecentlyDeleted` was a plain `%d` key, so it read
   "1 Fotos in „Zuletzt gelöscht“ bewegt." and "1 photos déplacées vers Supprimés récemment."
   — and "1 photos moved to Recently Deleted." in English, which had been shipping. It is a
   plural key now, in all seven languages.

2. **The history caption assumed more than one photo.**
   `cleanup.cleanupHistory.movedToRecentlyDeleted` sits directly under a count that is often
   1, but the Romance translations used an agreeing participle — French "Déplacées vers
   Supprimés récemment" under "1 photo". The caption carries no number of its own, so it
   cannot be a plural variation; `fr`, `es`, `es-419` and `pt-BR` now use a count-neutral noun
   phrase instead. German and Ukrainian were already neutral.

Both are covered by `CleanupToastPluralTests`.

## Findings — the two smart-category screens, German

Screenshot and blurred-photo cleanup were walked afterwards. The copy itself is clean at
110 and at 10 items — "110 Bildschirmfotos zur Durchsicht.",
"10 wahrscheinlich unscharfe Fotos zur Durchsicht.", "110 ausgewählt, geschätzte Größe
142,2 MB." — nothing clipped, plural forms right.

**One defect, fixed: the destructive button read like the button above it.** The screen
stacks "clear selection" directly on top of "delete selected". German had
`Auswahl aufheben` above `Auswahl löschen` — the second reads most naturally as clearing
the selection, which is what the first one does. French had `Effacer la sélection` above
`Supprimer la sélection`, two near-synonyms. On a button that moves photos out of the
library, that is a mis-tap waiting to happen.

German now says `Ausgewählte löschen` (names the photos, not the selection). French pairs
the clear action with the Select All label instead: `Tout sélectionner` / `Tout
désélectionner`. Spanish, Portuguese and Ukrainian were already unambiguous.

No rule catches this class, so `SelectionActionLabelTests` pins both labels in all seven
languages: a future translation change to either one fails the test and forces a second
look at the pair.

## Still owed

- The **double-length pseudo-locale pass** under the `Alike-Pseudolocale` scheme. RocketSim
  can drive it, but the scheme has to be launched from Xcode to inject the launch arguments;
  `simctl launch` can pass them too, and that is the cheaper route:
  `xcrun simctl launch <udid> com.alike.app -NSDoubleLocalizedStrings YES -NSShowNonLocalizedStrings YES -NSSurroundLocalizedStrings '[[]]'`
- `pt-BR`, `es` and `es-419` past the Welcome screens. The keys and layout are the same ones
  German and French exercised, so this is a length check rather than a correctness one.
- The delete confirmation inside the smart-category screens, and Cleanup history with more
  than one entry per month.

Watch for anything in CAPITALS under the pseudo-locale scheme: `-NSShowNonLocalizedStrings`
marks a string that never reached a catalog. The reminder-row bug above is what one looks
like when nobody runs that pass.
