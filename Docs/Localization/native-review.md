# Native review — what still needs a human

Task 40 translated 683 keys into `es-419`, `es`, `pt-BR`, `de` and `fr`; task 43 added
`it`, `nl`, `pl`, `tr` and `zh-Hant` on the same 683 keys. Every unit is marked
`state: "translated"`, so the catalogs read green in Xcode and the completeness tests
pass. **That is a statement about coverage, not about a native speaker having read it.**
This file is the list of strings where a wrong word costs money or a review flag, and it
is what a reviewer should be handed. The key tables below apply to every shipped language;
the per-language notes at the end say what to watch for in each.

Terminology was matched against Apple's own platform vocabulary per language rather than
a generic glossary — "Zuletzt gelöscht", "Supprimés récemment", "Eliminados
recientemente", "Apagados recentemente", "Eliminati di recente", "Recent verwijderd",
"Ostatnio usunięte", "Son Silinenler", "最近刪除". A reviewer should check that choice as
much as the grammar.

Three tier 3 terminology calls are the least certain and should be confirmed first:

| Term | Choice made | Why it is uncertain |
|---|---|---|
| Screenshot (`it`) | "screenshot" | Apple's Italian has used both "screenshot" and "istantanea schermo" across releases. Whichever the current iOS Photos album says is the one to use. |
| Screenshot (`zh-Hant`) | 螢幕快照 | Apple's zh-TW term, but 螢幕截圖 is far more common in everyday Taiwanese usage. This is a house-style call, not a correctness one. |
| Library (`tr`) | kitaplık | Apple's Turkish for a media library. "Kütüphane" reads more naturally to some, but would diverge from the Photos app. |

## Tier 1 — a wrong word here costs a refund or a rejection

### Subscription and paywall

`Packages/Purchases/Sources/PurchasesUI/Resources/Localizable.xcstrings`

| Key | Why |
|---|---|
| `purchases.subscriptionPaywall.subscriptionsRenewAutomaticallyUnlessCancelled` | Guideline 3.1.2 renewal terms. The 24-hour window is a fact, not phrasing. |
| `purchases.subscriptionPaywall.yearlyPlanIncludes7Day` | Trial length, what follows it, and how to cancel. Carries the eligibility hedge. |
| `purchases.subscriptionPaywall.billedYearly` / `.billedMonthly` | The period shown on the plan card, next to a StoreKit price. |
| `purchases.subscriptionPaywall.saveComparedWithMonthly` | A savings claim with a number in it. |
| `purchases.subscriptionPaywall.privacyPolicy` / `.termsOfUse` | The two required link labels. |
| `purchases.premium.freeIncludesScansPerCalendar` (+ `2`) | States the free allowance. Wrong here is a false advertisement. |
| `purchases.subscriptionPaywall.alikeFreeStillIncludesThree` | Same, from the other direction: what you keep without paying. |

`SubscriptionDisclosureTests` already asserts these stay byte-identical to
`Docs/legal/subscription-disclosure.md`, keep their numbers, and keep the eligibility
hedge. It cannot assert that the sentence reads naturally to a native speaker — that is
what this pass is for. **Change the document and the catalog together, or the test fails.**

### Deletion and cleanup confirmations

The user is about to move photos out of their library. Every one of these has to be
unambiguous about *where the photos go* and *that the space is not freed yet*.

| Catalog | Keys |
|---|---|
| `Core` | `selectedPhotoWillBeRemoved`, `selectedPhotosWillBeRemoved`, `selectedScreenshotWillBeRemoved`, `selectedScreenshotsWillBeRemoved`, `alertTitleScreenshots`, `alertTitleBlurredPhotos` |
| `Details` | `details.clusterDetails.deleteAlertTitle`, `.selectedPhotoWillBeRemoved`, `.selectedPhotosWillBeRemoved` |
| `Cleanup` | `cleanup.cleanupHistory.storageMayNotBeFreed`, `cleanup.main.photosMovedToRecentlyDeleted` |
| `Settings` | `settings.main.thisPermanentlyDeletesAlikesLocal`, `.thisActionCantBeUndone`, `.photoLibraryNeverDeletedBy`, `.deleteAllAlikeData` |

The Settings ones are a different risk from the rest: they promise the **photo library is
not touched**. A translation that blurs that line reads as "this app deletes your photos".

### Permission prompts

| Catalog | Keys |
|---|---|
| `Welcome` | `alikeNeedsPhotoAccessScan`, `photoAccessLetsAlikeScan`, `whyAlikeAsksPhotoAccess`, `alikeNeverDeletesPhotosAutomatically`, `photosStayPrivateYoullConfirm`, `analysisStaysDeviceNothingDeleted`, `canChangeAccessLaterSettings` |
| `Details` | `details.common.alikeNeedsPhotoLibraryAccess` |
| `Settings` | `settings.main.notificationsTurnedOffAlikeEnable` |

These make privacy claims: on-device analysis, nothing uploaded, nothing auto-deleted.
They have to stay *exactly* as strong as the English — no stronger.

The `NSPhotoLibraryUsageDescription` string in `Alike/Alike.xcodeproj` is **not** localized
and is out of scope here: it lives in the build settings
(`INFOPLIST_KEY_NSPhotoLibraryUsageDescription`), not in a catalog, so it shows in English
in every locale. Worth fixing, but it is a separate change — see the note in
`Docs/Localization/README.md`.

## Tier 2 — read it, but nothing breaks

`UserGuide` is 223 keys and by far the largest body of prose. It explains behaviour rather
than promising anything, so an awkward sentence is a quality problem, not a compliance one.
Two spots are worth a closer look because they state facts:

- `userGuide.settingsAndReminders.analysis.language.body` — lists the shipped languages.
  Tasks 40 and 43 each corrected it, in every locale; it will go stale again the next time
  a language is added. Treat it as part of the cost of adding one, not as a bug found later.
- `userGuide.freeAndPro.*` and `userGuide.scanning.status.allowance.body` — restate the
  free allowance and what Pro adds. They have to agree with the paywall copy above.

## The landing site — same review, different repository

The Privacy Policy, Terms of Use, support page and landing copy are published in
`de`, `fr`, `es`, `pt-BR`, `it`, `nl`, `pl`, `tr` and `zh-Hant` in
`alikeapp/alikeapp.github.io`. They were translated the same way the catalogs were —
carefully, against the same glossary, by someone who is not a native speaker of any of
the nine. **The same caveat applies: coverage, not a native pass.** Legal prose is the
one place where that gap costs more than awkwardness, so this is the part of the site a
reviewer should be handed first.

Sources are `<locale>/privacy.md`, `<locale>/terms.md` and `_data/<locale>.yml` in that
repository. Register per language matches the app: *du* for German, *vous* for French,
*tú* for Spanish, *você* for pt-BR, *tu* for Italian, *je* for Dutch, informal *ty* for
Polish and informal *sen* for Turkish — Turkish in particular, because a legal page is
where a translator's instinct reaches for *siz* and the app says *sen* everywhere else.

### Terms of Use — the compliance surface

`scripts/check-site.sh` asserts these are *present*. It cannot assert they are *right*.

| What | Why |
|---|---|
| The App Store EULA blockquote | Names Apple's Standard EULA as the licence that legally governs use and defers to it on conflict. `Docs/legal/README.md` records that dropping it is what turns this into a review problem. |
| The plans table | States the two durations and that the trial is yearly-only, for eligible new subscribers. |
| Billing and renewal bullets | The 24-hour cancellation window and the 24-hour pre-renewal charge are facts, not phrasing. |
| "We cannot cancel or refund ourselves" | Sets the expectation Apple actually enforces. A translation that softens this generates support mail we cannot act on. |
| Governing law + mandatory consumer rights | The second paragraph preserves local consumer protections. It must not read as a waiver. |
| The Apple section | Apple as third-party beneficiary, verbatim in substance. |

The two subscription disclosure paragraphs on the site were copied byte-for-byte from
`Docs/legal/subscription-disclosure.md`, so they need no separate review pass.

**They are an independent copy, not a reference.** Nothing propagates: the site is a
separate repository, `SubscriptionDisclosureTests` can only see the app catalog, and the
site's own `scripts/check-site.sh` greps short sentinel fragments — enough to catch a
*dropped* disclosure, not a stale one. Changing the wording is a three-place edit: this
repo's document, the catalog, and `_data/<locale>.yml` in the site repo. Run
`tools/check_site_legal_parity.py --require` after any of them to confirm all three
agree — bare, it skips and exits 0 when the site checkout is absent.

### Privacy Policy — the claims that must not drift

Every one of these is a factual claim about the app, and each must come out of the
translation exactly as strong as the English, and no stronger:

- Analysis runs on device via Vision; nothing is uploaded — no photo, thumbnail, or
  feature print.
- No analytics, no crash reporting, no advertising, no tracking, no cookies; the app
  makes no network requests of its own.
- Deletion always requires explicit confirmation, iOS confirms again, and photos land in
  Recently Deleted for ~30 days.
- Notification permission is requested *only* for the weekly cleanup reminder.
- Delete Alike Data erases local Alike data only — **not** photos, photo access, or the
  subscription. This is the same risk as the `settings.main.*` keys above: blur it and it
  reads as "this app deletes your photos".

### Landing copy — lower stakes, two exceptions

`_data/<locale>.yml` is marketing prose, so an awkward sentence is a quality problem. Two
entries state facts and have to agree with the app: the free allowance in `pricing.free`
("3 scans per month") and the language count in the last `features.items` entry.

## Per-language notes for the reviewer

- **`es-419` vs `es`** — these are separate texts on purpose. `es-419` uses "Configuración",
  "mes calendario", "agregar" and the simple preterite; `es` uses "Ajustes", "mes natural",
  "añadir" and the pretérito perfecto compuesto. If a reviewer finds them reading identically
  in a given string, that string is a bug in one of the two.
- **`de`** — the app addresses the user with *du* throughout, matching the existing English
  register. Check that no string slipped into *Sie*.
- **`fr`** — the app uses *vous*. Check the reverse.
- **`pt-BR`** — "apagar" for photos (matching Photos), "excluir" only where the English says
  "deletion" in the abstract.
- **`it`** — informal *tu*. The longest strings in the set after German, so it shares
  German's clipping risk on buttons and plan cards.
- **`nl`** — informal *je*. Compound nouns run long ("Schermafbeeldingen opruimen"); button
  labels are where that shows first.
- **`pl`** — informal *ty*. Four plural forms, and case endings mean a fragment key would be
  unsafe here even if one existed. The counts to eyeball are 1, 2, 5, 22, 25.
- **`tr`** — informal *sen*. Strings run 30–40% longer than English and suffixes attach to
  the noun, so nothing may be assembled from pieces. Numerals take a singular noun, which is
  why `one` and `other` read identically in the count-bearing keys — that is correct Turkish,
  not a copy-paste slip.
- **`zh-Hant`** — Taiwan/Hong Kong vocabulary. No plural forms at all. The thing to check is
  density rather than grammar: short labels leave a lot of empty button, and the
  numeric-heavy Cleanup screens set differently from Latin script.

## Not yet reviewed by a native speaker

Task 44 added the same five languages to the App Store listing — subtitle, keywords,
description, promotional text, release notes, the in-app-purchase display names, and the
five marketing screenshot captions — and to the landing site. That copy was written the
same way and carries the same caveat, with two places worth a reviewer's attention beyond
the app strings: **keywords**, which are market research rather than translation and are
the one field where a plausible-sounding word simply fails to be what people search for,
and the **zh-Hant screenshot captions**, which are the only copy in the project set in
Heiti TC rather than SF Pro and should be read at thumbnail size, not at full size.

No language in the app has had a native pass. The tier 3 five are the newest and the two
non-Latin-adjacent risks (`pl` grammar, `zh-Hant` terminology) are concentrated there, so if
review budget is limited, spend it on `pl` and `tr` first — Polish because wrong plural forms
are visible to every user on every count, Turkish because the paywall and deletion copy are
the longest strings in the app in that language.
