# Alike Release Checklist

The go-live gate. Work top to bottom; each step assumes the ones above it
passed. Nothing here is optional, and nothing here uploads anything until the
step that says it does.

Command reference: `Docs/ci-cd.md`. Branch and tag rules:
`Skills/GitFlow/ios-git-flow/SKILL.md` and its
`references/release-finalization.md`.

**Do not upload metadata, screenshots or IAP localizations while a version is in
App Review.** Steps 4, 5, 7 and 10 all write to App Store Connect, and writing to
a submission under review risks disturbing it for no gain — generated copy and
decks sit in the repo just as happily until the review clears. Generate and
validate whenever you like; upload when nothing is in review.

## 0. Environment

- [ ] `.env` present and loaded. It carries `ALIKE_PRIVACY_URL`,
      `ALIKE_SUPPORT_URL`, `ALIKE_TERMS_URL`, the optional
      `ALIKE_MARKETING_URL`, the four `ALIKE_REVIEW_*` App Review contact
      values, and `ALIKE_IAP_REVIEW_SCREENSHOT_PATH`. Every upload command
      refuses to run without the privacy and support URLs, by design.
      `ALIKE_TERMS_URL` is what the Privacy/Terms footer appended to every
      description points at — a stale value there ships a wrong link in the
      listing without failing anything.
- [ ] The per-locale URL overrides set for every non-English listing. These are
      optional and nothing fails without them — a listing simply reuses the
      English URLs, which is a silent localization gap rather than an error. The
      site now publishes all six locales, so leaving any of these unset sends
      readers to English legal text they were not reading a moment ago:

```sh
ALIKE_PRIVACY_URL_UK="https://alikeapp.github.io/uk/privacy/"
ALIKE_TERMS_URL_UK="https://alikeapp.github.io/uk/terms/"
ALIKE_SUPPORT_URL_UK="https://alikeapp.github.io/uk/support/"

ALIKE_PRIVACY_URL_DE_DE="https://alikeapp.github.io/de/privacy/"
ALIKE_TERMS_URL_DE_DE="https://alikeapp.github.io/de/terms/"
ALIKE_SUPPORT_URL_DE_DE="https://alikeapp.github.io/de/support/"

ALIKE_PRIVACY_URL_FR_FR="https://alikeapp.github.io/fr/privacy/"
ALIKE_TERMS_URL_FR_FR="https://alikeapp.github.io/fr/terms/"
ALIKE_SUPPORT_URL_FR_FR="https://alikeapp.github.io/fr/support/"

ALIKE_PRIVACY_URL_ES_ES="https://alikeapp.github.io/es/privacy/"
ALIKE_TERMS_URL_ES_ES="https://alikeapp.github.io/es/terms/"
ALIKE_SUPPORT_URL_ES_ES="https://alikeapp.github.io/es/support/"

# es-MX deliberately points at the same /es/ pages as es-ES. One Spanish page
# serves both listings: the legal copy does not need the regional vocabulary
# split, and /es/ advertises hreflang="es-419" for this storefront.
ALIKE_PRIVACY_URL_ES_MX="https://alikeapp.github.io/es/privacy/"
ALIKE_TERMS_URL_ES_MX="https://alikeapp.github.io/es/terms/"
ALIKE_SUPPORT_URL_ES_MX="https://alikeapp.github.io/es/support/"

ALIKE_PRIVACY_URL_PT_BR="https://alikeapp.github.io/pt-br/privacy/"
ALIKE_TERMS_URL_PT_BR="https://alikeapp.github.io/pt-br/terms/"
ALIKE_SUPPORT_URL_PT_BR="https://alikeapp.github.io/pt-br/support/"
```
- [ ] App Store Connect API credentials available to fastlane:
      `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID` and
      `APP_STORE_CONNECT_API_KEY_PATH` (or `..._API_KEY_CONTENT`). The same
      three are what `xcodebuild` authenticates with when it has to create a
      provisioning profile, so they matter before the upload step too.
- [ ] `xcode-select` points at the full Xcode, not the Command Line Tools —
      or don't bother: `tools/local_ci.sh` and `tools/local_cd.sh` both call
      `ensure_developer_dir` from `tools/xcode-env.sh` and fall back to the
      newest installed Xcode. Only an explicit `DEVELOPER_DIR` overrides it.
- [ ] **Signing, first release only.** The export step needs an *App Store
      distribution* profile for `com.alike.app`. A machine that has only ever
      built and run the app has an `Apple Development` certificate and a
      development profile — enough to archive, not enough to export, and the
      failure reads `No profiles for 'com.alike.app' were found`. Either create
      the distribution certificate once in Xcode → Settings → Accounts → Manage
      Certificates, or let `xcodebuild` create it:

```sh
set -a; . ./.env; set +a
ALIKE_XCODE_ALLOW_PROVISIONING_UPDATES=1 tools/upload-build
```

      That flag is what adds `-allowProvisioningUpdates` and the
      `-authenticationKey*` arguments. Without it `xcodebuild` only looks
      locally and never contacts the portal. The API key must be Admin or App
      Manager; a Developer key cannot create certificates.

## 1. Version and build

- [ ] Version chosen per `Skills/GitFlow/ios-git-flow/references/app-versioning.md`.
- [ ] Applied with the helper, not by hand:

```sh
Skills/GitFlow/ios-git-flow/scripts/bump-ios-version.sh \
  --version X.Y.Z --build N \
  --project Alike/Alike.xcodeproj/project.pbxproj --apply
```

- [ ] The bump is committed on `develop` **before** the release merge, so `main`
      never receives an unversioned release.
- [ ] No tag yet. Tags are created on the `main` merge commit, in step 9.

## 2. Code validation

- [ ] `tools/full` green — whitespace, every package's tests, and the full app
      compile gate with `xcodebuild -scheme Alike`.
- [ ] `tools/release-check X.Y.Z N` green — version check, bundle validation,
      Release archive, no-upload IPA export.
- [ ] No leftover debug flags, premium overrides or test endpoints.

## 3. Metadata

- [ ] Release notes updated for the release in `METADATA`
      (`tools/prepare_app_store_upload_bundle.py`), for all seven localizations
      the listing has: `en-US`, `uk`, `de-DE`, `fr-FR`, `es-ES`, `es-MX`,
      `pt-BR`. Validation fails if `METADATA` and `UPLOAD_SAFE_LOCALES` ever
      drift apart.
- [ ] Strict generation exits 0 with zero `TODO:` markers:

```sh
set -a; . ./.env; set +a; python3 tools/prepare_app_store_upload_bundle.py
```

- [ ] Every field inside its limit — subtitle 30 chars, keywords 100 chars
      including commas, promotional text 170 chars, description 4000 chars,
      release notes 4000 chars. The generator enforces these; a pass means they
      hold.
- [ ] `Docs/app-store-review-notes.txt` still describes the build being shipped:
      no account, why photo access is needed, on-device Vision, confirmed
      deletion into Recently Deleted, the three paywall entry points.
- [ ] `tools/meta` green.
- [ ] No price hardcoded in any copy. StoreKit supplies localized pricing.
- [ ] Listing copy does not contradict the published legal text in `Docs/legal/`.

## 4. Screenshots

- [ ] Deck rendered and eyeballed per locale — see `Docs/screenshot-brief.md`.
- [ ] Capture status table in `Docs/screenshot-shot-list.md` current.
- [ ] Privacy sweep on any new capture: faces, location giveaways, readable
      personal data, anything legible on a screen inside a photo.
- [ ] `tools/upload-screenshots`. Watch for at least one
      `Waiting for App Store Connect to publish screenshot checksums ...`, a
      single `Uploaded ...` block, and **no** `missing on App Store Connect`
      lines. Duplicates mean re-running, not repairing — see `Docs/ci-cd.md`.

## 5. In-app purchases

- [ ] `bundle exec ruby tools/app_store_iap_metadata.rb status` reflects the
      Alike Pro group and both plans.
- [ ] `upload-localizations` for the display names and descriptions in all seven
      localizations. Only `en-US` failures are fatal; App Store Connect rejecting
      another locale is reported as a warning and skipped.
- [ ] `upload-introductory-offers` for the yearly free trial.
- [ ] `upload-review-screenshots` — `ALIKE_IAP_REVIEW_SCREENSHOT_PATH` points at
      `Docs/images/review/11-paywall-disclosure.png`, which shows the renewal and
      trial disclosure App Review asks for.

## 6. Legal and support site

The site lives in its own repository, `alikeapp/alikeapp.github.io`, and deploys
on every push to that repository's `main`. It is **independent of this
repository's release merge**, so this whole step can and should be completed
*before* step 8 rather than after it — a dead Privacy Policy URL is grounds for
App Review rejection, and there is no longer any reason to discover that late.

- [ ] Pages source set to **GitHub Actions** (that repo's Settings → Pages).
- [ ] The workflow run succeeded. `scripts/check-site.sh` runs there on every
      pull request and again before each deploy, and asserts the locale matrix,
      internal links, hreflang, the Terms guardrails and — deliberately — that
      the rendered site references no third-party host, because the privacy
      policy claims Alike makes no network requests.
- [ ] All 24 published URLs return 200. The build already checked that each page
      exists in the rendered output; this checks the deployed site:

```sh
for l in "" uk/ de/ fr/ es/ pt-br/; do for p in "" privacy/ terms/ support/; do u="$l$p"; printf "%s %s\n" "$(curl -s -o /dev/null -w '%{http_code}' https://alikeapp.github.io/$u)" "/$u"; done; done
```

- [ ] In a **Release** build, the legal links open from all four entry points:
      the Scanner paywall, the cluster Details paywall, the Settings paywall,
      and Settings → Legal.

## 7. Text metadata upload

- [ ] `tools/text` — uploads localized text and App Review information.
      `privacy_url.txt` and `support_url.txt` go up per locale, so the Privacy
      and Support URLs need no manual entry in App Store Connect.

## 8. Release merge

- [ ] PR `develop` → `main`, titled for the release. Merge commit, never squash
      — release history is preserved on purpose.
- [ ] Required checks green: version check, build, tests, lint.
- [ ] Merged. The legal site is no longer published by this merge — it lives in
      `alikeapp/alikeapp.github.io` and step 6 should already be green before
      you get here.

## 9. Tag

- [ ] Annotated tag on the `main` merge commit, only after it exists:

```sh
git tag -a vX.Y.Z -m "Alike X.Y.Z"
```

- [ ] Pushed. Never tag `develop` for an app release.
- [ ] `main` merged back into `develop` so version and changelog changes stay on
      the integration branch.

## 10. Build upload

- [ ] `tools/upload-build X.Y.Z N`. It re-runs `release-check` first, uploads the
      Release IPA to TestFlight, and does **not** submit for review, notify
      external testers, or push tags. Add
      `ALIKE_XCODE_ALLOW_PROVISIONING_UPDATES=1` whenever the signing assets in
      step 0 are not already on the machine.
- [ ] Build processed in App Store Connect and attached to the version.

## 11. Submit

Manual, in App Store Connect:

- [ ] Version created, build attached, screenshots and text in place.
- [ ] App Review information filled — contact, notes, no demo account (there is
      none; `demo_account_required` is false and the demo fields are
      intentionally empty).
- [ ] **App Privacy questionnaire answered.** Nothing in the pipeline covers
      this — `deliver` uploads the privacy *URL* and nothing else, so the
      nutrition label is filled by hand and a version cannot be submitted until
      it is. Alike collects nothing: answer **"Data Not Collected"** for every
      category. Any other answer contradicts the published privacy policy and
      the app's own "no network requests" claim.
- [ ] Age rating and category answered. Export compliance should not be asked
      at all — `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` in the Xcode
      project answers it per build, matching `uses_non_exempt_encryption: false`
      in the Fastfile. The app implements no encryption of its own; if the
      question still appears, the answer is "None of the algorithms mentioned
      above".
- [ ] Subscription attached to the version for review.
- [ ] Submitted.

## 12. After submission

- [ ] Release branch state merged back everywhere it needs to be; `develop`
      green.
- [ ] Notion release task updated with the submitted version and build.
- [ ] Watch for App Review messages — rejections on a first submission usually
      concern the subscription disclosure or the legal links, both of which are
      evidenced by `Docs/images/review/`.
