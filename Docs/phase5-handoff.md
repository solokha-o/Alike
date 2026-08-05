# Phase 5 — Remaining Work

Handoff for whoever picks up the rest of Phase 5. Notion task 33 (privacy,
terms, subscription disclosure) is complete except for two acceptance criteria
that depend on publishing and on App Store Connect; those moved to tasks 34
and 35.

## State right now

| | |
|---|---|
| Branch | `feature/legal-and-app-store`, **1 commit unpushed** (`911e244`) |
| Site | Built and committed under `site/`, **never deployed** — all six URLs 404 |
| App | Ships `https://solokha-o.github.io/Alike/privacy/`, which is currently dead |
| Screenshots | 9 EN, 7 UK, at 1320×2868 in `Docs/images/` |
| App Store copy | **15 `TODO:` placeholders** in `tools/prepare_app_store_upload_bundle.py` |
| Validation | `tools/full` passes, including the app compile gate |

Background reading, all current: `Docs/ci-cd.md`, `Docs/legal/README.md`,
`Docs/legal/subscription-disclosure.md`, `Docs/screenshot-shot-list.md`.

---

## Task A — Write the App Store copy

**Delegable.** This is the largest remaining piece and needs no external access.

Replace the `METADATA` dict in `tools/prepare_app_store_upload_bundle.py`.
Fifteen placeholders across `en-US`, `en-GB` and `uk`, plus `APP_NAME`.

Hard limits, all enforced by the generator — it will fail the build if exceeded:

| Field | Limit |
|---|---|
| `APP_NAME` | 30 characters |
| `subtitle` | 30 characters |
| `keywords` | 100 UTF-8 **bytes** (Cyrillic costs 2 bytes/char) |
| `promotional_text` | 170 characters |
| `description` | 4000 characters |

Constraints on the content itself:

- Claims must match what the app does. The privacy policy and the landing page
  already state: on-device Vision analysis, nothing uploaded, no analytics, no
  account, deletion always confirmed and recoverable from Recently Deleted. Do
  not write anything that contradicts those — they are published legal text.
- Free tier is 3 scans/month and one-photo-at-a-time cleanup. Alike Pro adds
  unlimited scans, batch cleanup, screenshot cleanup, blurred-photo cleanup,
  advanced filters, and custom reminders. Source: `PremiumFeature` and
  `PremiumAccessPolicy` in `Packages/Core/Sources/Core/Models/PremiumAccess.swift`.
- Never hardcode a price in copy; StoreKit supplies localized pricing.
- `en-GB` may reuse `en-US` copy, but check spelling (*organise*, *colour*).

Also update `Docs/app-store-review-notes.txt` — it is still `TODO:` scaffolding.
It should explain photo access, on-device analysis, confirmed deletion, and that
there is no account to sign into.

**Verify:**

```sh
ALIKE_PRIVACY_URL="https://solokha-o.github.io/Alike/privacy/" ALIKE_SUPPORT_URL="https://solokha-o.github.io/Alike/support/" python3 tools/prepare_app_store_upload_bundle.py
```

Strict mode must pass with **zero** `TODO:` errors. It will still complain about
App Review contact values until `ALIKE_REVIEW_*` are set — that is expected and
not part of this task.

---

## Task B — Publish the site

**Partly delegable.** Steps 1 and 4 are ordinary git work; 2 and 3 need the
GitHub web UI.

1. Push `feature/legal-and-app-store`, open a PR into `develop`, merge, then
   merge `develop` into `main`. The Pages workflow triggers **only on `main`**.
2. *(needs web UI)* Repo Settings → Pages → set source to **GitHub Actions**.
   Without this nothing deploys and the URLs stay 404.
3. *(needs web UI)* Confirm the workflow run in the Actions tab succeeds. It
   fails the build deliberately if the rendered site references any third-party
   host — the privacy policy claims Alike makes no network requests, so a web
   font or analytics script would make that claim false.
4. Verify:

```sh
for u in "" privacy/ uk/privacy/ terms/ uk/terms/ support/; do printf "%s %s\n" "$(curl -s -o /dev/null -w '%{http_code}' https://solokha-o.github.io/Alike/$u)" "$u"; done
```

All six must return **200**. Until they do, the app links to a dead page and
App Review will reject the build.

Note: `alike.github.io` is not obtainable — `alike` is an existing GitHub
account. This is a project Pages site, so `site/_config.yml` sets
`baseurl: "/Alike"`. Removing that breaks every absolute URL by one path segment.

---

## Task C — App Store Connect

**Not delegable** — web UI and account access.

- Privacy Policy URL → `https://solokha-o.github.io/Alike/privacy/`
- Support URL → `https://solokha-o.github.io/Alike/support/`

Put the same two in `.env` as `ALIKE_PRIVACY_URL` and `ALIKE_SUPPORT_URL`. The
upload commands refuse to run without them, by design.

Also replace `AppStoreLinks.appID` in
`Packages/Core/Sources/Core/Models/AppStoreLinks.swift` — still the placeholder
`"0000000000"`, so Share App and Rate on App Store currently point nowhere.

---

## Task D — Remaining screenshots

**Not delegable** unless the simulator route is used — needs a device or a
booted simulator.

Four shots missing, plus UK versions of 6 and 8. Priority order:

| Shot | Why |
|---|---|
| 11. Paywall with renewal + trial disclosure | App Review evidence for the subscription |
| 10. Settings showing the Legal section | App Review evidence for the legal links |
| 9. History | Fills the last landing-page frame |
| 12. User Guide hub | Optional |

Capture at 1125×2436 or larger, drop into `~/Downloads`, add the filename to the
`SHOTS` dict in `tools/import_device_screenshots.py`, then:

```sh
python3 tools/import_device_screenshots.py --source ~/Downloads
```

It upscales to the required 1320×2868 and emits the 520px landing-page copies.

For the simulator route, `xcode-select` currently points at the Command Line
Tools; the native simulator integration needs:

```sh
sudo xcode-select -s /Applications/Xcode-26.6.0.app/Contents/Developer
```

**Before publishing any of these:** the captures are a real photo library.
**Shot 5 UK (`05-comparison-review`) shows a laptop screen with legible content
in two thumbnails.** Review that frame, and check all of them for recognisable
faces and location-revealing images. `tools/generate_demo_library.py` builds a
synthetic nature library if you would rather not publish real photos.

---

## Known gaps worth fixing, not blocking release

- **`Packages/Storage` tests do not run under SwiftPM.** `PersistenceController`
  traps with "Failed to load Core Data model" because SwiftPM does not compile
  the `.xcdatamodeld`. `tools/local_ci.sh` skips the package via
  `SWIFTPM_UNSUPPORTED_PACKAGES`; the code is still covered by the app compile
  gate. Fix by declaring the model as a `.process` resource and loading from
  `Bundle.module`.
- **No per-plan trial badge on the paywall.** The disclosure paragraph covers
  Guideline 3.1.2 in prose, but the yearly card itself does not show the trial.
  Doing it properly needs `Product.SubscriptionInfo.isEligibleForIntroOffer`
  plumbed through `StoreKitClient` and `SubscriptionProduct`, so ineligible
  customers are never shown trial copy.

---

## Definition of done for Phase 5

1. All six site URLs return 200.
2. Strict metadata generation passes with no `TODO:` remaining.
3. Privacy and support URLs set in App Store Connect.
4. In a **Release** build, both legal links open from the Scanner paywall, the
   Details paywall, the Settings paywall, and Settings → Legal.
5. `tools/full` passes.

Items 1 and 4 are what task 33 could not close.
