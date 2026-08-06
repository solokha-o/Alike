# Task 34 — Prepare App Store Connect listing, support URL, review notes

Implementation plan. Scope is the *listing text and review information* — the
site deploy (task 35) and the screenshot backlog are tracked separately.

## Current state

| | |
|---|---|
| `tools/prepare_app_store_upload_bundle.py` | 15 `TODO:` placeholders + `APP_NAME` |
| `Docs/app-store-review-notes.txt` | still `TODO:` scaffolding |
| `AppStoreLinks.appID` | placeholder `"0000000000"` — real ID is `6798399598` |
| Privacy / support URLs | paths chosen, site committed but never deployed (all six 404) |
| Strict generation | refuses to run while any `TODO:` remains |

## Step 1 — Localized App Store copy

Replace the `METADATA` dict and `APP_NAME` in
`tools/prepare_app_store_upload_bundle.py` for `en-US`, `en-GB`, `uk`.

Per-locale fields: `subtitle`, `description`, `keywords`, `promotional_text`,
`release_notes`.

Hard limits, enforced by the generator's strict mode:

| Field | Limit |
|---|---|
| `APP_NAME` | 30 characters |
| `subtitle` | 30 characters |
| `keywords` | 100 UTF-8 **bytes** (Cyrillic = 2 bytes/char) |
| `promotional_text` | 170 characters |
| `description` | 4000 characters |

Content constraints:

- Claims must match the published legal text (`Docs/legal/`) and the landing
  page: on-device Vision analysis, nothing uploaded, no analytics, no account,
  deletion always confirmed and recoverable from Recently Deleted. Those pages
  are legal copy — the listing must not contradict them.
- Free tier: 3 scans/month, one-photo-at-a-time cleanup. Alike Pro: unlimited
  scans, batch cleanup, screenshot cleanup, blurred-photo cleanup, advanced
  filters, custom reminders. Source of truth is `PremiumFeature` /
  `PremiumAccessPolicy` in
  `Packages/Core/Sources/Core/Models/PremiumAccess.swift`.
- Never hardcode a price — StoreKit supplies localized pricing.
- `en-GB` may reuse `en-US` copy but must use British spelling (*organise*,
  *colour*).
- The generator appends the Privacy and Terms links to every description
  (`description_with_links`); do not add them by hand.

## Step 2 — App Review notes

Rewrite `Docs/app-store-review-notes.txt` as final prose (the file is read by
`review_notes_text()` and written to `metadata/review_information/notes.txt`).
It must cover:

- No account, no sign-in; `demo_user.txt` / `demo_password.txt` are
  intentionally empty and `demo_account_required` is false.
- Why photo library access is required, and that Full Access (or Limited Access
  with several similar photos selected) is needed to exercise the app.
- All analysis is on-device via the Vision framework; nothing leaves the device.
- Deletion requires explicit confirmation and moves photos to Recently Deleted.
- Alike Pro is auto-renewable; the paywall is reachable from Scanner, cluster
  Details, and Settings, and discloses the yearly free trial.

## Step 3 — Support and privacy URLs

- Privacy Policy URL: `https://solokha-o.github.io/Alike/privacy/`
- Support URL: `https://solokha-o.github.io/Alike/support/`

Put both in `.env` as `ALIKE_PRIVACY_URL` and `ALIKE_SUPPORT_URL`; the upload
commands refuse to run without them. Enter the same two values in App Store
Connect (manual, needs account access).

## Step 4 — App Review contact

Set `ALIKE_REVIEW_FIRST_NAME`, `ALIKE_REVIEW_LAST_NAME`, `ALIKE_REVIEW_EMAIL`,
`ALIKE_REVIEW_PHONE` in `.env`. Strict mode fails with "Real App Review contact
values are required" until these are real.

## Step 5 — Publish the site

The task cannot be verified while the six URLs 404.

1. Push `feature/legal-and-app-store`, PR into `develop`, merge, then merge
   `develop` into `main`. The Pages workflow triggers **only on `main`**.
2. *(web UI)* Settings → Pages → source **GitHub Actions**.
3. *(web UI)* Confirm the Actions run succeeds. It deliberately fails if the
   rendered site references any third-party host.
4. Verify:

```sh
for u in "" privacy/ uk/privacy/ terms/ uk/terms/ support/; do printf "%s %s\n" "$(curl -s -o /dev/null -w '%{http_code}' https://solokha-o.github.io/Alike/$u)" "$u"; done
```

## Step 6 — App ID

Replace `AppStoreLinks.appID` in
`Packages/Core/Sources/Core/Models/AppStoreLinks.swift` with `6798399598` —
still `"0000000000"`, so Share App and Rate on App Store currently point
nowhere. This one edit touches app source, so it needs the compile gate.

## Step 7 — Release-build link check

Once the pages are live, confirm in a **Release** build that the legal links
open from the Scanner paywall, the cluster Details paywall, the Settings
paywall, and Settings → Legal. This is the criterion task 33 could not close.

## Verification

```sh
ALIKE_PRIVACY_URL="https://solokha-o.github.io/Alike/privacy/" \
ALIKE_SUPPORT_URL="https://solokha-o.github.io/Alike/support/" \
python3 tools/prepare_app_store_upload_bundle.py
```

Strict mode must report **zero** `TODO:` errors and no length violations.
Until `ALIKE_REVIEW_*` are set it will still flag the contact values — expected
until step 4.

After step 5, run the full compile gate:

```sh
xcodebuild -project Alike/Alike.xcodeproj -scheme Alike -destination 'id=66E5E039-9C66-4878-B211-923932320166' build
```

Then `tools/full`.

## Done when

1. Strict metadata generation passes with no `TODO:` remaining, all three
   locales within limits.
2. `Docs/app-store-review-notes.txt` is final prose, no scaffolding.
3. Privacy and Support URLs are set in App Store Connect and in `.env`.
4. App Review contact fields are real.
5. All six site URLs return 200.
6. `AppStoreLinks.appID` is `6798399598` and the app compiles.
7. Legal links verified from all four entry points in a Release build.
8. `tools/full` passes.

## Out of scope

- Remaining screenshots (paywall with trial disclosure, Settings → Legal,
  History, User Guide hub). The first two are App Review evidence and should
  land before submission.
- Per-plan trial badge on the paywall; prose disclosure already covers 3.1.2.
