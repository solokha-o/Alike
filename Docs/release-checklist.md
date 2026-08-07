# Alike Release Checklist

The go-live gate. Work top to bottom; each step assumes the ones above it
passed. Nothing here is optional, and nothing here uploads anything until the
step that says it does.

Command reference: `Docs/ci-cd.md`. Branch and tag rules:
`Skills/GitFlow/ios-git-flow/SKILL.md` and its
`references/release-finalization.md`.

## 0. Environment

- [ ] `.env` present and loaded. It carries `ALIKE_PRIVACY_URL`,
      `ALIKE_SUPPORT_URL`, `ALIKE_TERMS_URL`, the optional
      `ALIKE_MARKETING_URL`, the four `ALIKE_REVIEW_*` App Review contact
      values, and `ALIKE_IAP_REVIEW_SCREENSHOT_PATH`. Every upload command
      refuses to run without the privacy and support URLs, by design.
      `ALIKE_TERMS_URL` is what the Privacy/Terms footer appended to every
      description points at — a stale value there ships a wrong link in the
      listing without failing anything.
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
      (`tools/prepare_app_store_upload_bundle.py`), for `en-US` and `uk` — the
      two localizations the listing has. Validation fails if `METADATA` and
      `UPLOAD_SAFE_LOCALES` ever drift apart.
- [ ] Strict generation exits 0 with zero `TODO:` markers:

```sh
set -a; . ./.env; set +a; python3 tools/prepare_app_store_upload_bundle.py
```

- [ ] Every field inside its limit — subtitle 30 chars, keywords 100 UTF-8
      bytes, promotional text 170 chars, description 4000 chars, release notes
      4000 chars. The generator enforces these; a pass means they hold.
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
- [ ] `upload-localizations` for the `en-US` / `uk` display names and
      descriptions.
- [ ] `upload-introductory-offers` for the yearly free trial.
- [ ] `upload-review-screenshots` — `ALIKE_IAP_REVIEW_SCREENSHOT_PATH` points at
      `Docs/images/review/11-paywall-disclosure.png`, which shows the renewal and
      trial disclosure App Review asks for.

## 6. Legal and support site

The site deploys from `.github/workflows/pages.yml`, which triggers **only on
`main`** — so this step cannot pass before the release merge in step 8.

- [ ] Pages source set to **GitHub Actions** (repo Settings → Pages, web UI).
- [ ] The workflow run succeeded. It fails deliberately if the rendered site
      references any third-party host, because the privacy policy claims Alike
      makes no network requests.
- [ ] All six URLs return 200:

```sh
for u in "" privacy/ uk/privacy/ terms/ uk/terms/ support/; do printf "%s %s\n" "$(curl -s -o /dev/null -w '%{http_code}' https://solokha-o.github.io/Alike/$u)" "$u"; done
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
- [ ] Merged. This is what publishes the legal site, so step 6 runs immediately
      after and must pass before submission.

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
- [ ] Age rating, category, export compliance answered.
- [ ] Subscription attached to the version for review.
- [ ] Submitted.

## 12. After submission

- [ ] Release branch state merged back everywhere it needs to be; `develop`
      green.
- [ ] Notion release task updated with the submitted version and build.
- [ ] Watch for App Review messages — rejections on a first submission usually
      concern the subscription disclosure or the legal links, both of which are
      evidenced by `Docs/images/review/`.
