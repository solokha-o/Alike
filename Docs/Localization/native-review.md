# Native review — what still needs a human

Task 40 translated 683 keys into `es-419`, `es`, `pt-BR`, `de` and `fr`; task 43 added
`it`, `nl`, `pl`, `tr` and `zh-Hant`, and task 45 added `ar`, all on the same 683 keys. Every unit is marked
`state: "translated"`, so the catalogs read green in Xcode and the completeness tests
pass. **That is a statement about coverage, not about a native speaker having read it.**
This file is the list of strings where a wrong word costs money or a review flag, and it
is what a reviewer should be handed. The key tables below apply to every shipped language;
the per-language notes at the end say what to watch for in each.

Terminology follows the words Apple's iPhone User Guide uses in each language for the Photos
app, checked on 2026-10-29 against "Delete or hide photos and videos on iPhone"
(`support.apple.com/<locale>/guide/iphone/iphb4defbde9/ios`). The Recently Deleted album is
"Zuletzt gelöscht" (`de`), "Supprimées récemment" (`fr`, `fr-CA`), "Eliminados" (`es`,
`es-419`), "Apagados" (`pt-BR`), "Apagado" (`pt-PT`), "Eliminati di recente" (`it`), "Recent
verwijderd" (`nl`), "Ostatnio usunięte" (`pl`), "Son Silinenler" (`tr`), "Недавно видалені"
(`uk`), "最近刪除" (`zh-Hant`) and "المحذوفة مؤخرًا" (`ar`). Apple renames these between iOS
releases, so check them again when a new iOS ships, and change every string that names the
album at once — a partial rename shows the user two names for one album.

Three tier 3 terminology calls were the least certain:

| Term | Choice made | Why it is uncertain |
|---|---|---|
| Screenshot (`it`) | "screenshot" | Confirmed 2026-10-29: Apple's Italian guide says "Scattare uno screenshot". |
| Screenshot (`zh-Hant`) | 截圖 | Changed 2026-10-29 from 螢幕快照: Apple's zh-TW guide now says 拍攝截圖, and 截圖 is the everyday word. |
| Library (`tr`) | arşiv | Changed 2026-10-29 from "kitaplık": Apple's Turkish guide says "Fotoğraf arşivi", and the app already used "arşiv" in 11 strings and the store text. |

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

The `NSPhotoLibraryUsageDescription` prompt makes the same claims and adds one more: the
original is always kept, so an enhancement can be reverted. It lives in
`Alike/Alike/InfoPlist.xcstrings`, not in a package catalog — see "The permission prompt"
in `Docs/Localization/README.md`.

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

### Landing review pass 2 — 2026-10-30

On the same date, Codex repeated the review using the local
`localized-copy-review` workflow: semantic comparison, fluency, legal claim scope,
and marketing clarity. Follow-up edits in site PR #15 clarify who learns from
photo choices and who resets that learning, and improve permission descriptions,
sensitivity instructions, layout wording and privacy headlines across the 9
locales. The Italian privacy list now retains the source's explicit exclusion of
renting personal data. In `it`, `nl`, `pl`, `tr` and `zh-Hant`, the privacy
governing-law sentence now preserves consumer data-protection rights specifically,
matching English rather than adding a separate general consumer-rights clause.
The Terms' mandatory consumer protections remain unchanged. Both subscription
disclosures remain untouched. No additional Terms edits were needed in this pass.
No tests, builds, site checks or legal parity checks ran during the repeat review.

Codex completed an AI copy review of `<locale>/privacy.md`, `<locale>/terms.md`
and `_data/<locale>.yml` for `de`, `fr`, `es`, `pt-BR`, `it`, `nl`, `pl`, `tr`
and `zh-Hant`. The proposed edits are in
[site PR #15](https://github.com/alikeapp/alikeapp.github.io/pull/15), on
`docs/native-review-pass-2`, with one commit per locale. This records an AI review,
not a native-speaker or legal sign-off.

The pass corrected album names in French, Spanish and Brazilian Portuguese;
Turkish `arşiv` terminology and informal commands; Traditional Chinese `截圖`;
Italian sign-in wording; intellectual-property scope; and literal marketing
phrases. It retained the EULA priority, plan durations, trial eligibility,
24-hour billing windows, Apple refund limits, mandatory consumer rights and
Apple's third-party-beneficiary rights. Landing copy now limits Delete Alike Data
to local Alike data and qualifies the yearly trial for eligible new subscribers.
The free allowance remains 3 scans per month.

The requested localization skill lists 12 locales, but the current InfoPlist,
PurchasesUI and Core catalogs contain 18, matching `knownRegions` without `Base`.
The translated feature entry therefore says **18 language variants**, including
regional English, French and Portuguese variants, and lists them. No site locale
or page was added. After the review, the owner chose the 18-variant count for the
whole site, so `en`, `uk` and `ar` now say the same; before that change they still
said thirteen and the site stated two numbers. The older 12-locale skill
list and 17-locale review-log count need a separate correction.

The current English privacy policy describes optional MetricKit crash reports
sent by the user. The pass preserved that scope and its exclusion of third-party
crash-reporting services; it did not add an absolute claim of no crash reports.

Checks after the review, on 2026-10-30:

- `tools/check_site_legal_parity.py --require` failed on `main` and on the PR
  branch: the last sentence of `pricing.disclosure_trial` in `pl` and `ar` had
  drifted from `Docs/legal/subscription-disclosure.md`. The site is the copy, so
  site PR #15 now restores both values from the document; the document and the
  catalog did not change. All 24 disclosure strings now match.
- `scripts/test-check-site.sh` passed 51 of 51 regression tests, and
  `scripts/check-site.sh` passed on the rendered site, before and after that fix.

Still open:

- Native-speaker and legal sign-off remain open for all 18 reviewed legal pages,
  especially liability and mandatory consumer-rights clauses. The PRs are not
  merged. The Notion card status remains unchanged.

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
- **`ar`** — Modern Standard Arabic, and the only right-to-left language in the set. Three
  things to check that no other language raises. **Direction:** the whole interface mirrors,
  so a reviewer should look at layout as much as wording. **Plurals:** all six CLDR
  categories are declared and four of them share the same wording — that is correct, not a
  copy-paste slip; the forms that differ are `two` ("صورتان") and `few` ("صور"). **The brand
  name:** "Alike" stays in Latin script inline in Arabic sentences, which is the usual Apple
  practice, but a reviewer should confirm the surrounding grammar agrees with it and that no
  string reads awkwardly around the embedded Latin run. Glyphs also sit taller than Latin
  ones, so fixed-height labels are where clipping shows first.

## Review log

| Date | Locales | Who | What | Pull requests |
|---|---|---|---|---|
| 2026-10-27 | `ar`, `pl`, `tr`, `en-GB`, `fr-CA`, `pt-PT` | Codex (AI text review) | Tier 1 keys, tier 2 facts, App Store copy; `en-GB`, `fr-CA`, `pt-PT` added as full locales | #120, #138, #142, #143, #144, #145, #146 |
| 2026-10-27 | `en-CA`, `en-AU`, `de`, `fr`, `it`, `nl`, `es`, `es-419`, `pt-BR`, `uk`, `zh-Hant` | Codex (AI text review) | Same scope; `en-CA`, `en-AU` added as full locales | #148–#158 |
| 2026-10-29 | `fr`, `fr-CA`, `es`, `es-419`, `pt-BR`, `uk`, `zh-Hant` | Independent AI reviewer, then Claude | Album and screenshot names made consistent in every string and matched to Apple's iPhone User Guide | #151, #154–#158 |
| 2026-10-29 | All 17 locales | Oleksandr Solokha (product owner) | Accepted the AI review pass for release in place of a native-speaker sign-off, and confirmed the `ar`/`pl`/`tr` device check | — |
| 2026-10-30 | All 18 listing locales: `en-US`, `en-GB`, `en-CA`, `en-AU`, `uk`, `de-DE`, `fr-FR`, `fr-CA`, `es-ES`, `es-MX`, `pt-BR`, `pt-PT`, `it`, `nl-NL`, `pl`, `tr`, `zh-Hant`, `ar-SA` | AI text review (listing) | Card 49: trial eligibility in English promotional text, Ukrainian catalog terms, French learning-reset wording, Canadian French grammar, Portuguese register, monthly IAP descriptions and screenshot captions; keywords unchanged | [#164](https://github.com/solokha-o/Alike/pull/164) |
| 2026-10-30 | All 18 listing locales; `uk` widget strings | Claude (follow-up to the review's open questions) | Descriptions count 18 language variants, as the site does; the trial sentence carries the 24-hour cancellation deadline from disclosure paragraph 2; "always reversible" became "original always one tap away"; the `uk` widget and enhancement-error strings use фототека; `tr` and `uk` widget captures retaken and the changed captions re-rendered | [#164](https://github.com/solokha-o/Alike/pull/164) |

Placeholders, plural categories and the disclosure text were checked mechanically for every
locale, and `tools/full` passed on `develop` after the last merge. These checks
predate the card 49 listing review; that review ran no validation.

## Not yet reviewed by a native speaker

**Every locale has had an AI review pass, and the product owner accepted it for release on
2026-10-29. No locale has been signed off by a native speaker.** The product owner
confirmed the `ar`, `pl` and `tr` device checks (layout, mirroring, plural forms at 1, 2, 5,
22, 25) on 2026-10-29. The AI pass
fixed wording and consistency; it cannot replace a person who reads the language every day.

Card 49 reviewed all 18 App Store listing locales on 2026-10-30. This was an
AI text review, accepted by the product owner in place of a native-speaker review.
No native speaker has signed off the listing. The pass covered subtitles,
descriptions, promotional text, release notes, keywords, IAP names and descriptions,
and all 7 screenshot captions per source deck. Existing rendered images were
inspected at about 230 pixels wide, starting with `zh-Hant`, `de`, `it` and `tr`.
The follow-up re-rendered the changed captions and retook the `tr` and `uk` widget
captures on an iPhone 18 Pro Max simulator (iOS 27.2) with a staged widget snapshot.

**Keywords and rendered captions still need a person.** Search demand needs market
knowledge, including for the unchanged Apple Ads keywords in `it`, `nl-NL` and `pl`.
A person must review caption density and legibility, especially `zh-Hant` in Heiti TC.
The `zh-Hant` keywords 大師, 神器 and 快照 stay: the first two are common in Taiwanese
cleaner-app names, and 快照 catches searches that still use Apple's older term for
screenshots. No popularity data backs them yet. The disclosure document and the
PurchasesUI catalog did not change; the listing now quotes them more closely.

When a native speaker is available, spend the budget in this order: `ar` first, because it
is the only language where a translation error and a *layout* error look the same to a
non-reader — the paywall and the deletion confirmations first; then `pl` and `tr` — Polish
because wrong plural forms are visible to every user on every count, Turkish because the
paywall and deletion copy are the longest strings in the app in that language.
