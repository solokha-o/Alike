# Native review — what still needs a human

Task 40 translated 683 keys into `es-419`, `es`, `pt-BR`, `de` and `fr`. Every unit is
marked `state: "translated"`, so the catalogs read green in Xcode and the completeness
tests pass. **That is a statement about coverage, not about a native speaker having read
it.** This file is the list of strings where a wrong word costs money or a review flag,
and it is what a reviewer should be handed.

Terminology was matched against Apple's own platform vocabulary per language rather than
a generic glossary — "Zuletzt gelöscht", "Supprimés récemment", "Eliminados
recientemente", "Apagados recentemente", "Bildschirmfotos", "Captures d'écran". A
reviewer should check that choice as much as the grammar.

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
  Task 40 corrected it; it will go stale again the next time a language is added.
- `userGuide.freeAndPro.*` and `userGuide.scanning.status.allowance.body` — restate the
  free allowance and what Pro adds. They have to agree with the paywall copy above.

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
