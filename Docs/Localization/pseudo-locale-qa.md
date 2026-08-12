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

## Findings — es-419, es and pt-BR on a real library

Walked on device from screenshots, on a build that predates the two Cleanup fixes above.

**No new defects.** The cleanup queue, both smart-category screens at 128 and 10 items,
cluster details at 1 and 6 selected, the review action bar, and the history screen with
several entries in one month all render correctly. Nothing clipped; the longest line,
`128 seleccionadas, tamaño estimado 166,9 MB.`, fits on one line, and
`6 seleccionadas, tamaño estimado 27,4 MB.` wraps cleanly to two.

Two things worth recording:

- **The `es-419` / `es` split is visible in the running app**, which is the point of
  shipping them separately: the tab bar reads `Configuración` in `es-419` and `Ajustes`
  in `es`. Same for `Quitar selección` / `Eliminar seleccionadas`, which are
  unambiguous in both — unlike the German and French pair fixed above.
- **The history-caption defect reproduces in Spanish and Portuguese**
  (`Movidas a Eliminados recientemente` under `1 foto`), on a build from before the fix.
  That is confirmation the fix was needed in those languages too, not a new finding.

`Mover 1 foto` / `Mover 6 fotos` confirm the review action bar's new plural key resolving
on device.

## Findings — the delete confirmation in de, fr, es and pt-BR

The cluster-details confirmation was walked at 1 and at 3 selected in all four languages.
**No defects.** Both halves of the key pair render in full, with correct agreement:

- `fr` — "La photo sélectionnée sera retirée … conservée … sa suppression définitive"
  against "Les photos … seront retirées … conservées … leur suppression"
- `de` — "Das ausgewählte Foto wird … bleibt … wenn es endgültig gelöscht ist" against
  "Die ausgewählten Fotos werden … bleiben … wenn sie … sind"
- `pt-BR` — "A foto … será removida … ficará … ela seja apagada" against "As fotos …
  serão removidas … ficarão … elas sejam apagadas"
- `es` — "La foto … se eliminará … permanecerá … se elimine" against "Las fotos …
  se eliminarán … permanecerán … se eliminen"

This is the pair `xcstringstool` will not accept as a plural variation, so it stays two
top-level strings picked in Swift. Seeing both halves on screen in four languages is the
only way to know the second one agrees — a catalog test cannot judge that.

Titles and action bars matched throughout: "Déplacer 3 photos", "3 Fotos bewegen",
"Mover 3 fotos", and their singular forms.

## Findings — the smart-category confirmation, de / fr / es / pt-BR

The last screen that had only been seen in Ukrainian. Walked at 1 and at 136 selected in
all four languages. **No defects.** `core.cleanupCategory.alertTitle*` and its message pair
inflect the category noun and agree with the count:

- `de` — "1 ausgewähltes Bildschirmfoto … bewegen?" / "136 ausgewählte Bildschirmfotos …",
  bodies "Das … wird … wenn es endgültig gelöscht ist" against "Die … werden … wenn sie …"
- `fr` — "Déplacer 1 capture d'écran sélectionnée …" / "… 136 captures d'écran
  sélectionnées …", "conservée … sa suppression" against "conservées … leur suppression"
- `es` — "¿Mover 1 captura de pantalla seleccionada …?" / "… 136 capturas …?"
- `pt-BR` — "Mover 1 captura de tela selecionada …?" / "… 136 capturas de tela …?"

The German title hyphenates across lines ("Bildschirm-fotos") at 136 selected. That is
normal German typesetting in a system alert, not truncation.

## Copy fix — the button said "Delete", the action is a move

Not a translation defect. The smart-category button read `Delete Selected` in English and
the six translations followed it faithfully, while the same action on the cluster screen
said `Move N Photos` and the confirmation it opens says `Move … to Recently Deleted?`.
Nothing is deleted on that tap: the photos go to Recently Deleted and stay 30 days, which
the rest of the app's copy is careful to say.

`details.screenshotCleanupComponents.deleteSelected` → `.moveSelected` (`Move Selected`,
`Ausgewählte bewegen`, `Déplacer la sélection`, `Mover seleccionadas`, `Mover selecionadas`,
`Перемістити вибране`), and `.deleting` → `.moving` so the in-progress label follows the
verb. `SelectionActionLabelTests` now also fails if either label promises deletion in any
of the seven languages.

The pair stays distinguishable from the button above it in every language, which was the
earlier fix on this same screen.

## Still owed

- The **double-length pseudo-locale pass** under the `Alike-Pseudolocale` scheme. RocketSim
  can drive it, but the scheme has to be launched from Xcode to inject the launch arguments;
  `simctl launch` can pass them too, and that is the cheaper route:
  `xcrun simctl launch <udid> com.alike.app -NSDoubleLocalizedStrings YES -NSShowNonLocalizedStrings YES -NSSurroundLocalizedStrings '[[]]'`

Every screen in the acceptance list has now been walked on device in the languages that
matter. Every defect this task found was a wrong string rather than a layout failure, which
is why the pseudo-locale pass above is the one worth keeping on the list: it targets the
failure mode nothing else here exercised.

Watch for anything in CAPITALS under the pseudo-locale scheme: `-NSShowNonLocalizedStrings`
marks a string that never reached a catalog. The reminder-row bug above is what one looks
like when nobody runs that pass.
